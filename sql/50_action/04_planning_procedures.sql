-- =============================================================================
-- 50_action / 04 — accept or reject a schedule suggestion          STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-79 (accept / reject-with-reason through the action service),
--              ADR-0018 ("acceptance goes through CMP-10 ... no second write path")
-- Proves     : T-74 (the accept/reject half; DQ-PLAN-ACCEPT-REJECT in 15_quality/08)
-- Authority  : ADR-0005 (approval, idempotency, audit first), ADR-0018
-- Parameter  : <% database %>
--
-- Same shape as 02_action_procedures.sql: idempotency check, validation against
-- the engine AS IT STANDS NOW, audit row, then the write, in one transaction.
--
-- ACCEPT does not create work: it schedules drafts that already exist. Every
-- component in the suggestion must have an open draft (SP_DRAFT_WORK_ORDER),
-- and every window must still be a FEASIBLE row of ENG_WINDOW_CANDIDATE — a
-- rebuilt engine can retire a window, and accepting a retired one would schedule
-- work on a day the engine no longer vouches for.
--
-- REJECT shares ACT_DECISION with the draft rejection but not its vocabulary
-- (ADR-0018 / Q-81): a planner rejects a schedule for scheduling reasons.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

alter table ACTION.ACT_WORK_ORDER_DRAFT add column if not exists window_id varchar(40);
alter table ACTION.ACT_WORK_ORDER_DRAFT add column if not exists window_start date;
alter table ACTION.ACT_WORK_ORDER_DRAFT add column if not exists window_end date;
alter table ACTION.ACT_WORK_ORDER_DRAFT add column if not exists suggestion_id varchar(40);

create or replace procedure ACTION.SP_ACCEPT_SUGGESTION(
    P_SUGGESTION_ID   varchar,
    P_IDEMPOTENCY_KEY varchar,
    P_ON_BEHALF_OF    varchar default null
)
returns variant
language sql
execute as owner
as
$$
declare
    audit_failed exception (-20035, 'Audit append failed, so nothing was written (FR-37)');
    v_user     varchar default current_user();
    v_role     varchar default current_role();
    v_selftest boolean default startswith(coalesce(P_IDEMPOTENCY_KEY, ''), 'SELFTEST-');
    v_outcome  varchar default 'APPLIED';
    v_reason   varchar default null;
    v_id       varchar default uuid_string();
    v_n        integer;
    v_type     varchar;
    v_items    integer;
    v_stale    integer;
    v_nodraft  varchar;
    v_done     integer;
    v_audit    integer;
    v_fault    boolean;
begin
    select count(*) into :v_n from ACTION.ACT_DECISION where idempotency_key = :P_IDEMPOTENCY_KEY;
    if (v_n > 0) then
        select max(decision_id) into :v_id from ACTION.ACT_DECISION where idempotency_key = :P_IDEMPOTENCY_KEY;
        v_outcome := 'DUPLICATE';
        v_reason  := 'This acceptance was already recorded; nothing changed.';
    else
        select count(*), max(suggestion_type) into :v_n, :v_type
          from ENGINE.ENG_SUGGESTION where suggestion_id = :P_SUGGESTION_ID;
        select count(*),
               count_if(c.window_id is null or not c.is_feasible or c.crew_id <> i.crew_id or c.part_number <> i.part_number)
          into :v_items, :v_stale
          from ENGINE.ENG_SUGGESTION_ITEM i
          left join ENGINE.ENG_WINDOW_CANDIDATE c on c.window_id = i.window_id
         where i.suggestion_id = :P_SUGGESTION_ID;
        select listagg(i.component_id, ', ') into :v_nodraft
          from ENGINE.ENG_SUGGESTION_ITEM i
         where i.suggestion_id = :P_SUGGESTION_ID
           and not exists (select 1 from ACTION.ACT_WORK_ORDER_DRAFT d
                           where d.component_id = i.component_id and d.status = 'DRAFT'
                             and d.is_selftest = :v_selftest);
        -- Suggestion ids are deterministic, so a self-test's decision would block
        -- the next verify run. For SELFTEST keys only, "already decided" is scoped
        -- to the same run (key prefix SELFTEST-DQ-<timestamp>).
        select count(*) into :v_done from ACTION.ACT_DECISION
         where subject_type = 'SCHEDULE_SUGGESTION' and subject_id = :P_SUGGESTION_ID
           and is_selftest = :v_selftest
           and (not :v_selftest
                or startswith(idempotency_key, coalesce(regexp_substr(:P_IDEMPOTENCY_KEY, '^SELFTEST-DQ-[0-9]+'), :P_IDEMPOTENCY_KEY)));

        if (not is_role_in_session('WOA_PLANNER')) then
            v_reason := 'Only planning (WOA_PLANNER) may accept a schedule.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (v_n <> 1) then
            v_reason := 'No such suggestion in the current engine run.';
        elseif (v_type = 'INFEASIBLE') then
            v_reason := 'This suggestion reports that no feasible window exists; there is nothing to accept.';
        elseif (v_stale > 0) then
            v_reason := v_stale || ' of ' || v_items || ' windows are no longer feasible in the engine. Rebuild and choose again.';
        elseif (v_nodraft is not null and length(v_nodraft) > 0) then
            v_reason := 'Draft the work order first for: ' || v_nodraft || '.';
        elseif (v_done > 0) then
            v_reason := 'A decision has already been recorded on this suggestion.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, evidence, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'ACCEPT_SUGGESTION', 'SCHEDULE_SUGGESTION', :P_SUGGESTION_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('suggestion_id', :P_SUGGESTION_ID),
           (select object_construct('type', max(s.suggestion_type), 'crew', max(s.crew_id),
                                    'start', max(s.start_day), 'end', max(s.end_day),
                                    'windows', array_agg(i.window_id))
              from ENGINE.ENG_SUGGESTION s join ENGINE.ENG_SUGGESTION_ITEM i on i.suggestion_id = s.suggestion_id
             where s.suggestion_id = :P_SUGGESTION_ID),
           :v_selftest;
    v_audit := sqlrowcount;
    select enabled into :v_fault from OPS.OPS_TEST_HOOK where hook = 'FAIL_AUDIT';
    if (v_audit <> 1 or (v_fault and v_outcome = 'APPLIED')) then
        raise audit_failed;
    end if;

    if (v_outcome = 'APPLIED') then
        insert into ACTION.ACT_DECISION (decision_id, subject_type, subject_id, decision, reason_code, note,
                                         decided_by, decided_role, on_behalf_of, decided_at,
                                         idempotency_key, is_selftest)
        select :v_id, 'SCHEDULE_SUGGESTION', :P_SUGGESTION_ID, 'ACCEPT', 'ACCEPTED', null,
               :v_user, :v_role, :P_ON_BEHALF_OF, current_timestamp()::timestamp_ntz,
               :P_IDEMPOTENCY_KEY, :v_selftest;
        update ACTION.ACT_WORK_ORDER_DRAFT d
           set window_status = 'SCHEDULED',
               window_id     = i.window_id,
               window_start  = i.start_day,
               window_end    = i.end_day,
               crew_id       = i.crew_id,
               suggestion_id = i.suggestion_id,
               window_note   = 'Scheduled ' || to_varchar(i.start_day) || ' to ' || to_varchar(i.end_day)
                               || ' with ' || i.crew_id || ', engine window ' || i.window_id
                               || ', from suggestion ' || i.suggestion_id || '.'
          from ENGINE.ENG_SUGGESTION_ITEM i
         where i.suggestion_id = :P_SUGGESTION_ID
           and d.component_id = i.component_id and d.status = 'DRAFT' and d.is_selftest = :v_selftest;
        v_reason := 'Schedule accepted: ' || sqlrowcount || ' draft(s) now carry an engine window. The work order still needs approval.';
    end if;
    commit;

    return object_construct('outcome', v_outcome, 'decision_id', iff(v_outcome = 'APPLIED', v_id, null),
                            'message', v_reason);
exception
    when other then
        rollback;
        raise;
end;
$$;

create or replace procedure ACTION.SP_REJECT_SUGGESTION(
    P_SUGGESTION_ID   varchar,
    P_REASON_CODE     varchar,
    P_NOTE            varchar,
    P_IDEMPOTENCY_KEY varchar,
    P_ON_BEHALF_OF    varchar default null
)
returns variant
language sql
execute as owner
as
$$
declare
    audit_failed exception (-20035, 'Audit append failed, so nothing was written (FR-37)');
    v_user     varchar default current_user();
    v_role     varchar default current_role();
    v_selftest boolean default startswith(coalesce(P_IDEMPOTENCY_KEY, ''), 'SELFTEST-');
    v_outcome  varchar default 'APPLIED';
    v_reason   varchar default null;
    v_id       varchar default uuid_string();
    v_n        integer;
    v_done     integer;
    v_audit    integer;
    v_fault    boolean;
begin
    select count(*) into :v_n from ACTION.ACT_DECISION where idempotency_key = :P_IDEMPOTENCY_KEY;
    if (v_n > 0) then
        select max(decision_id) into :v_id from ACTION.ACT_DECISION where idempotency_key = :P_IDEMPOTENCY_KEY;
        v_outcome := 'DUPLICATE';
        v_reason  := 'This rejection was already recorded.';
    else
        select count(*) into :v_n from ENGINE.ENG_SUGGESTION where suggestion_id = :P_SUGGESTION_ID;
        -- Suggestion ids are deterministic, so a self-test's decision would block
        -- the next verify run. For SELFTEST keys only, "already decided" is scoped
        -- to the same run (key prefix SELFTEST-DQ-<timestamp>).
        select count(*) into :v_done from ACTION.ACT_DECISION
         where subject_type = 'SCHEDULE_SUGGESTION' and subject_id = :P_SUGGESTION_ID
           and is_selftest = :v_selftest
           and (not :v_selftest
                or startswith(idempotency_key, coalesce(regexp_substr(:P_IDEMPOTENCY_KEY, '^SELFTEST-DQ-[0-9]+'), :P_IDEMPOTENCY_KEY)));
        if (not is_role_in_session('WOA_PLANNER')) then
            v_reason := 'Only planning (WOA_PLANNER) may reject a schedule.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (P_REASON_CODE is null or P_REASON_CODE not in
                ('CREW_PREFERENCE', 'CUSTOMER_OUTAGE', 'BUNDLE_DIFFERENTLY', 'RISK_DISPUTED', 'OTHER')) then
            v_reason := 'Reason must be one of CREW_PREFERENCE, CUSTOMER_OUTAGE, BUNDLE_DIFFERENTLY, RISK_DISPUTED, OTHER.';
        elseif (P_REASON_CODE = 'OTHER' and (P_NOTE is null or length(trim(P_NOTE)) < 10)) then
            v_reason := 'OTHER needs a note of at least 10 characters.';
        elseif (v_n <> 1) then
            v_reason := 'No such suggestion in the current engine run.';
        elseif (v_done > 0) then
            v_reason := 'A decision has already been recorded on this suggestion.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'REJECT_SUGGESTION', 'SCHEDULE_SUGGESTION', :P_SUGGESTION_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('suggestion_id', :P_SUGGESTION_ID, 'reason_code', :P_REASON_CODE, 'note', :P_NOTE),
           :v_selftest;
    v_audit := sqlrowcount;
    select enabled into :v_fault from OPS.OPS_TEST_HOOK where hook = 'FAIL_AUDIT';
    if (v_audit <> 1 or (v_fault and v_outcome = 'APPLIED')) then
        raise audit_failed;
    end if;

    if (v_outcome = 'APPLIED') then
        insert into ACTION.ACT_DECISION (decision_id, subject_type, subject_id, decision, reason_code, note,
                                         decided_by, decided_role, on_behalf_of, decided_at,
                                         idempotency_key, is_selftest)
        select :v_id, 'SCHEDULE_SUGGESTION', :P_SUGGESTION_ID, 'REJECT', :P_REASON_CODE, :P_NOTE,
               :v_user, :v_role, :P_ON_BEHALF_OF, current_timestamp()::timestamp_ntz,
               :P_IDEMPOTENCY_KEY, :v_selftest;
        v_reason := 'Suggestion rejected (' || P_REASON_CODE || '). Recorded in the audit.';
    end if;
    commit;

    return object_construct('outcome', v_outcome, 'decision_id', iff(v_outcome = 'APPLIED', v_id, null),
                            'message', v_reason);
exception
    when other then
        rollback;
        raise;
end;
$$;

grant usage on procedure ACTION.SP_ACCEPT_SUGGESTION(varchar, varchar, varchar)                   to role WOA_PLANNER;
grant usage on procedure ACTION.SP_REJECT_SUGGESTION(varchar, varchar, varchar, varchar, varchar) to role WOA_PLANNER;
