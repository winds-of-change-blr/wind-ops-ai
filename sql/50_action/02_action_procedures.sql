-- =============================================================================
-- 50_action / 02 — the only write path: approval procedures       STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-32, FR-34..FR-37, ADR-0005 (M10)
-- Proves     : T-29, T-30, T-33, T-34, T-35 (self-tested by 15_quality/06)
-- Authority  : ADR-0005 flowchart, AGENTS.md rule 3
-- Parameter  : <% database %>
--
-- Every procedure follows ADR-0005's flowchart, in this order:
--
--   1. IDEMPOTENCY  the key was seen before -> return the existing record,
--                   write nothing new to ACTION (T-34)
--   2. RE-VALIDATE  re-read the engine; never trust the caller, which is a UI.
--                   Any failed check -> REFUSED, with the reason (T-29)
--   3. AUDIT FIRST  one AUD_ACTION row per request, refusals included, then
--                   verify the row landed. If not -> raise, roll back, nothing
--                   written (T-35)
--   4. WRITE        the state change, in the same transaction as the audit
--
-- EXECUTE AS OWNER, so a caller needs no privilege on the tables at all — only
-- USAGE on the procedure (03_action_grants). CURRENT_USER() inside an owner's-
-- rights procedure is still the CALLER (probed 2026-09-26: returns NIRAJ, not
-- the owner), so the audit records who acted. The persona check uses
-- IS_ROLE_IN_SESSION as well as the grant: two locks, either one sufficient.
--
-- ON_BEHALF_OF: the Streamlit app runs as its owner, so CURRENT_USER() cannot
-- see the human in front of it. The app passes the viewer's name here, and it
-- is recorded BESIDE, never instead of, CURRENT_USER(). It is a caller-supplied
-- label, not an authentication — ADR-0020's owner's-rights limitation.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- -----------------------------------------------------------------------------
-- Suppress one alarm incident, time-boxed. Guards: FR-32 and ADR-0017.
-- -----------------------------------------------------------------------------
create or replace procedure ACTION.SP_APPROVE_SUPPRESSION(
    P_INCIDENT_ID     varchar,
    P_HOURS           number,
    P_REASON          varchar,
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
    v_turbine  varchar;
    v_code     varchar;
    v_safety   boolean;
    v_elevated boolean;
    v_class    varchar;
    v_risky    integer default 0;
    v_audit    integer;
    v_fault    boolean;
begin
    -- 1. Idempotency
    select count(*) into :v_n from ACTION.ACT_SUPPRESSION where idempotency_key = :P_IDEMPOTENCY_KEY;
    if (v_n > 0) then
        select max(suppression_id) into :v_id from ACTION.ACT_SUPPRESSION where idempotency_key = :P_IDEMPOTENCY_KEY;
        v_outcome := 'DUPLICATE';
        v_reason  := 'This request was already applied; returning the existing suppression.';
    end if;

    -- 2. Re-validate against the engine, most fundamental refusal first
    if (v_outcome = 'APPLIED') then
        select count(*) into :v_n from ENGINE.ENG_INCIDENT where incident_id = :P_INCIDENT_ID;
        if (v_n = 1) then
            select turbine_id, alarm_code, is_safety_critical, is_elevated, incident_class
              into :v_turbine, :v_code, :v_safety, :v_elevated, :v_class
              from ENGINE.ENG_INCIDENT where incident_id = :P_INCIDENT_ID;
            select count(*) into :v_risky from ENGINE.ENG_ALERT_RANKED
             where turbine_id = :v_turbine and risk_band in ('HIGH', 'MEDIUM');
        end if;

        if (not is_role_in_session('WOA_RMC')) then
            v_reason := 'Only the remote monitoring centre (WOA_RMC) may suppress alarms.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (P_REASON is null or length(trim(P_REASON)) < 10) then
            v_reason := 'A reason of at least 10 characters is required; suppression is an explicit human act.';
        elseif (P_HOURS is null or P_HOURS < 1 or P_HOURS > 168) then
            v_reason := 'Suppressions are time-boxed: between 1 and 168 hours.';
        elseif (v_n <> 1) then
            v_reason := 'No such incident.';
        elseif (v_safety) then
            v_reason := v_code || ' is a safety-critical alarm code. Safety-critical alarms are never suppressed.';
        elseif (v_elevated) then
            v_reason := 'This asset carries elevated evidence (an anomaly flag within 3 days, or a CMS alarm within 7). Nothing is suppressed on an elevated asset.';
        elseif (v_risky > 0) then
            v_reason := v_turbine || ' has ' || v_risky || ' component(s) at MEDIUM or HIGH failure risk. Nothing is suppressed on an elevated-risk asset (FR-32).';
        elseif (v_class <> 'NUISANCE') then
            v_reason := 'Only incidents the engine classed NUISANCE may be suppressed; this one is ' || v_class || '. UNDETERMINED is left for a human and never hidden.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    -- 3 + 4. Audit first, then write, in one transaction
    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, evidence, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'APPROVE_SUPPRESSION', 'INCIDENT', :P_INCIDENT_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('incident_id', :P_INCIDENT_ID, 'hours', :P_HOURS, 'reason', :P_REASON),
           object_construct('turbine_id', :v_turbine, 'alarm_code', :v_code, 'is_safety_critical', :v_safety,
                            'is_elevated', :v_elevated, 'incident_class', :v_class,
                            'components_at_medium_or_high_risk', :v_risky),
           :v_selftest;
    v_audit := sqlrowcount;
    select enabled into :v_fault from OPS.OPS_TEST_HOOK where hook = 'FAIL_AUDIT';
    if (v_audit <> 1 or (v_fault and v_outcome = 'APPLIED')) then
        raise audit_failed;
    end if;

    if (v_outcome = 'APPLIED') then
        insert into ACTION.ACT_SUPPRESSION (suppression_id, incident_id, turbine_id, alarm_code, reason,
                                            approved_by, approved_role, on_behalf_of, approved_at, expires_at,
                                            status, idempotency_key, is_selftest)
        select :v_id, :P_INCIDENT_ID, :v_turbine, :v_code, :P_REASON,
               :v_user, :v_role, :P_ON_BEHALF_OF, current_timestamp()::timestamp_ntz,
               dateadd(hour, :P_HOURS, current_timestamp())::timestamp_ntz,
               'ACTIVE', :P_IDEMPOTENCY_KEY, :v_selftest;
        v_reason := 'Suppressed for ' || P_HOURS || ' h. Reversible from the Command Center; recorded in the audit.';
    end if;
    commit;

    return object_construct('outcome', v_outcome, 'suppression_id', iff(v_outcome = 'REFUSED', null, v_id),
                            'message', v_reason);
exception
    when other then
        rollback;
        raise;
end;
$$;

-- -----------------------------------------------------------------------------
-- Reverse a suppression. A new audited event, never a deletion (T-30).
-- -----------------------------------------------------------------------------
create or replace procedure ACTION.SP_REVOKE_SUPPRESSION(
    P_SUPPRESSION_ID  varchar,
    P_REASON          varchar,
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
    v_n        integer;
    v_status   varchar;
    v_audit    integer;
    v_fault    boolean;
begin
    select count(*) into :v_n from ACTION.AUD_ACTION
     where idempotency_key = :P_IDEMPOTENCY_KEY and action_type = 'REVOKE_SUPPRESSION' and outcome = 'APPLIED';
    if (v_n > 0) then
        v_outcome := 'DUPLICATE';
        v_reason  := 'This revocation was already applied.';
    else
        select count(*), max(status) into :v_n, :v_status from ACTION.ACT_SUPPRESSION
         where suppression_id = :P_SUPPRESSION_ID;
        if (not is_role_in_session('WOA_RMC')) then
            v_reason := 'Only the remote monitoring centre (WOA_RMC) may revoke a suppression.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (P_REASON is null or length(trim(P_REASON)) < 10) then
            v_reason := 'A reason of at least 10 characters is required.';
        elseif (v_n <> 1) then
            v_reason := 'No such suppression.';
        elseif (v_status <> 'ACTIVE') then
            v_reason := 'This suppression is ' || v_status || ', not ACTIVE.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'REVOKE_SUPPRESSION', 'SUPPRESSION', :P_SUPPRESSION_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('suppression_id', :P_SUPPRESSION_ID, 'reason', :P_REASON), :v_selftest;
    v_audit := sqlrowcount;
    select enabled into :v_fault from OPS.OPS_TEST_HOOK where hook = 'FAIL_AUDIT';
    if (v_audit <> 1 or (v_fault and v_outcome = 'APPLIED')) then
        raise audit_failed;
    end if;

    if (v_outcome = 'APPLIED') then
        update ACTION.ACT_SUPPRESSION
           set status = 'REVOKED', revoked_by = :v_user, revoked_at = current_timestamp()::timestamp_ntz,
               revoke_reason = :P_REASON
         where suppression_id = :P_SUPPRESSION_ID;
        v_reason := 'Suppression revoked; the alarm is back in the queue.';
    end if;
    commit;

    return object_construct('outcome', v_outcome, 'suppression_id', P_SUPPRESSION_ID, 'message', v_reason);
exception
    when other then
        rollback;
        raise;
end;
$$;

-- -----------------------------------------------------------------------------
-- Draft a work order for an engine-ranked component. US-32: engine candidates
-- only — the component must be MEDIUM or HIGH in ENG_ALERT_RANKED right now.
--
-- The part is the costliest part of the component class: the SAME part
-- ENG_ALERT_RANKED costs the expected loss on (max(unit_cost_inr)), so the
-- draft and the ranking that justified it cannot disagree. The window is NOT
-- scheduled: ENG_WINDOW_CANDIDATE (FR-33) does not exist yet, and a draft that
-- invented a date would be exactly the false confirmation ADR-0005 forbids.
-- -----------------------------------------------------------------------------
create or replace procedure ACTION.SP_DRAFT_WORK_ORDER(
    P_COMPONENT_ID    varchar,
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
    v_band     varchar;
    v_part     varchar;
    v_doc      varchar;
    v_open     varchar;
    v_audit    integer;
    v_fault    boolean;
begin
    select count(*) into :v_n from ACTION.ACT_WORK_ORDER_DRAFT where idempotency_key = :P_IDEMPOTENCY_KEY;
    if (v_n > 0) then
        select max(draft_id) into :v_id from ACTION.ACT_WORK_ORDER_DRAFT where idempotency_key = :P_IDEMPOTENCY_KEY;
        v_outcome := 'DUPLICATE';
        v_reason  := 'This draft already exists; returning it.';
    else
        select count(*), max(r.risk_band), max(p.part_number), max(m.doc_id)
          into :v_n, :v_band, :v_part, :v_doc
          from ENGINE.ENG_ALERT_RANKED r
          left join (select part_number, component_class_code from RAW.DIM_PART
                     qualify row_number() over (partition by component_class_code
                                                order by unit_cost_inr desc, part_number) = 1) p
                 on p.component_class_code = r.component_class_code
          left join DOCS.DOC_PART_PROCEDURE m on m.part_number = p.part_number
         where r.component_id = :P_COMPONENT_ID;
        select max(draft_id) into :v_open from ACTION.ACT_WORK_ORDER_DRAFT
         where component_id = :P_COMPONENT_ID and status = 'DRAFT' and is_selftest = :v_selftest;

        if (not is_role_in_session('WOA_PLANNER')) then
            v_reason := 'Only planning (WOA_PLANNER) may draft work orders.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (v_n <> 1) then
            v_reason := 'The engine has no ranked risk for this component.';
        elseif (v_band not in ('HIGH', 'MEDIUM')) then
            v_reason := 'The engine rates this component ' || v_band || '. Drafts are made only for MEDIUM or HIGH risk (US-32).';
        elseif (v_part is null or v_doc is null) then
            v_reason := 'No part or no approved procedure is mapped for this component class, so a draft could not cite one.';
        elseif (v_open is not null) then
            v_reason := 'An open draft already exists for this component: ' || v_open || '.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, evidence, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'DRAFT_WORK_ORDER', 'COMPONENT', :P_COMPONENT_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('component_id', :P_COMPONENT_ID),
           object_construct('risk_band', :v_band, 'part_number', :v_part, 'procedure_doc_id', :v_doc),
           :v_selftest;
    v_audit := sqlrowcount;
    select enabled into :v_fault from OPS.OPS_TEST_HOOK where hook = 'FAIL_AUDIT';
    if (v_audit <> 1 or (v_fault and v_outcome = 'APPLIED')) then
        raise audit_failed;
    end if;

    if (v_outcome = 'APPLIED') then
        insert into ACTION.ACT_WORK_ORDER_DRAFT (
            draft_id, component_id, turbine_id, site_code, component_class_name, scope,
            part_number, part_name, part_lead_time_days, requires_crane, stock_on_hand,
            procedure_doc_id, procedure_section,
            risk_probability, risk_band, anomaly_flag, top_drivers, expected_loss_inr, model_version,
            risk_as_of_date, window_status, window_note, crew_id, status,
            drafted_by, drafted_at, idempotency_key, is_selftest)
        select :v_id, r.component_id, r.turbine_id, r.site_code, r.component_class_name,
               'Replace ' || p.part_name || ' on ' || r.turbine_id || ' (' || r.component_class_name
                   || '), per ' || m.doc_id || '. Risk ' || r.risk_band || ' ('
                   || to_varchar(round(r.risk_probability * 100, 1)) || '% in 30 days) as of '
                   || to_varchar(r.as_of_date) || '.',
               p.part_number, p.part_name, p.lead_time_days, coalesce(p.requires_crane, false),
               (select coalesce(sum(quantity_on_hand - quantity_reserved), 0) from RAW.DIM_STOCK s
                 where s.part_number = p.part_number),
               m.doc_id, m.section,
               r.risk_probability, r.risk_band, r.anomaly_flag, r.top_drivers::varchar, r.expected_loss_inr,
               r.model_version, r.as_of_date,
               'NOT_SCHEDULED',
               'No maintenance window chosen: the window engine (FR-33, ENG_WINDOW_CANDIDATE) is not built. The planner schedules this manually.',
               null, 'DRAFT', :v_user, current_timestamp()::timestamp_ntz, :P_IDEMPOTENCY_KEY, :v_selftest
          from ENGINE.ENG_ALERT_RANKED r
          join (select * from RAW.DIM_PART
                qualify row_number() over (partition by component_class_code
                                           order by unit_cost_inr desc, part_number) = 1) p
            on p.component_class_code = r.component_class_code
          join DOCS.DOC_PART_PROCEDURE m on m.part_number = p.part_number
         where r.component_id = :P_COMPONENT_ID;
        v_reason := 'Draft created. It needs a planner''s approval before anything is written as a work order.';
    end if;
    commit;

    return object_construct('outcome', v_outcome, 'draft_id', iff(v_outcome = 'REFUSED', v_open, v_id),
                            'message', v_reason);
exception
    when other then
        rollback;
        raise;
end;
$$;

-- -----------------------------------------------------------------------------
-- Approve a draft into a work order. Re-validates the draft against the engine
-- as it stands NOW (ADR-0005 "re-validated"): a draft whose risk has fallen or
-- whose score is from an older run is refused, not silently approved.
-- One work order per draft and per key (T-34).
-- -----------------------------------------------------------------------------
create or replace procedure ACTION.SP_APPROVE_WORK_ORDER(
    P_DRAFT_ID        varchar,
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
    v_user      varchar default current_user();
    v_role      varchar default current_role();
    v_selftest  boolean default startswith(coalesce(P_IDEMPOTENCY_KEY, ''), 'SELFTEST-');
    v_outcome   varchar default 'APPLIED';
    v_reason    varchar default null;
    v_id        varchar default uuid_string();
    v_n         integer;
    v_status    varchar;
    v_component varchar;
    v_asof      date;
    v_now_band  varchar;
    v_now_asof  date;
    v_audit     integer;
    v_fault     boolean;
begin
    select count(*) into :v_n from ACTION.ACT_WORK_ORDER
     where idempotency_key = :P_IDEMPOTENCY_KEY or draft_id = :P_DRAFT_ID;
    if (v_n > 0) then
        select max(work_order_id) into :v_id from ACTION.ACT_WORK_ORDER
         where idempotency_key = :P_IDEMPOTENCY_KEY or draft_id = :P_DRAFT_ID;
        v_outcome := 'DUPLICATE';
        v_reason  := 'A work order already exists for this request or this draft; returning it. No second work order was created.';
    else
        select count(*), max(status), max(component_id), max(risk_as_of_date)
          into :v_n, :v_status, :v_component, :v_asof
          from ACTION.ACT_WORK_ORDER_DRAFT where draft_id = :P_DRAFT_ID;
        select max(risk_band), max(as_of_date) into :v_now_band, :v_now_asof
          from ENGINE.ENG_ALERT_RANKED where component_id = :v_component;

        if (not is_role_in_session('WOA_PLANNER')) then
            v_reason := 'Only planning (WOA_PLANNER) may approve work orders.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (v_n <> 1) then
            v_reason := 'No such draft.';
        elseif (v_status <> 'DRAFT') then
            v_reason := 'This draft is ' || v_status || ' and cannot be approved.';
        elseif (v_now_asof is null or v_now_asof <> v_asof) then
            v_reason := 'The risk score has been refreshed since this draft was made (' || to_varchar(v_asof)
                        || ' vs ' || coalesce(to_varchar(v_now_asof), 'none') || '). Re-draft from the current score.';
        elseif (v_now_band not in ('HIGH', 'MEDIUM')) then
            v_reason := 'The engine now rates this component ' || v_now_band || '. Re-check before approving.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, evidence, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'APPROVE_WORK_ORDER', 'DRAFT', :P_DRAFT_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('draft_id', :P_DRAFT_ID),
           (select object_construct('component_id', component_id, 'part_number', part_number,
                                    'procedure_doc_id', procedure_doc_id, 'risk_probability', risk_probability,
                                    'risk_band', risk_band, 'top_drivers', top_drivers,
                                    'expected_loss_inr', expected_loss_inr, 'model_version', model_version,
                                    'risk_as_of_date', risk_as_of_date, 'current_band', :v_now_band)
              from ACTION.ACT_WORK_ORDER_DRAFT where draft_id = :P_DRAFT_ID),
           :v_selftest;
    v_audit := sqlrowcount;
    select enabled into :v_fault from OPS.OPS_TEST_HOOK where hook = 'FAIL_AUDIT';
    if (v_audit <> 1 or (v_fault and v_outcome = 'APPLIED')) then
        raise audit_failed;
    end if;

    if (v_outcome = 'APPLIED') then
        insert into ACTION.ACT_WORK_ORDER (work_order_id, draft_id, component_id, turbine_id, part_number,
                                           procedure_doc_id, approved_by, approved_role, on_behalf_of,
                                           approved_at, status, idempotency_key, is_selftest)
        select :v_id, draft_id, component_id, turbine_id, part_number, procedure_doc_id,
               :v_user, :v_role, :P_ON_BEHALF_OF, current_timestamp()::timestamp_ntz,
               'APPROVED_NOT_SCHEDULED', :P_IDEMPOTENCY_KEY, :v_selftest
          from ACTION.ACT_WORK_ORDER_DRAFT where draft_id = :P_DRAFT_ID;
        update ACTION.ACT_WORK_ORDER_DRAFT set status = 'APPROVED' where draft_id = :P_DRAFT_ID;
        v_reason := 'Work order approved and recorded. It is not yet scheduled: no window, crew or crane has been booked.';
    end if;
    commit;

    return object_construct('outcome', v_outcome, 'work_order_id', iff(v_outcome = 'REFUSED', null, v_id),
                            'message', v_reason);
exception
    when other then
        rollback;
        raise;
end;
$$;

-- -----------------------------------------------------------------------------
-- Reject a draft with a reason. ACT_DECISION, draft-side vocabulary (Q-81).
-- -----------------------------------------------------------------------------
create or replace procedure ACTION.SP_REJECT_WORK_ORDER_DRAFT(
    P_DRAFT_ID        varchar,
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
    v_status   varchar;
    v_audit    integer;
    v_fault    boolean;
begin
    select count(*) into :v_n from ACTION.ACT_DECISION where idempotency_key = :P_IDEMPOTENCY_KEY;
    if (v_n > 0) then
        select max(decision_id) into :v_id from ACTION.ACT_DECISION where idempotency_key = :P_IDEMPOTENCY_KEY;
        v_outcome := 'DUPLICATE';
        v_reason  := 'This rejection was already recorded.';
    else
        select count(*), max(status) into :v_n, :v_status from ACTION.ACT_WORK_ORDER_DRAFT
         where draft_id = :P_DRAFT_ID;
        if (not is_role_in_session('WOA_PLANNER')) then
            v_reason := 'Only planning (WOA_PLANNER) may reject drafts.';
        elseif (P_IDEMPOTENCY_KEY is null or length(trim(P_IDEMPOTENCY_KEY)) < 8) then
            v_reason := 'An idempotency key of at least 8 characters is required.';
        elseif (P_REASON_CODE is null or P_REASON_CODE not in
                ('NOT_NEEDED', 'ALREADY_PLANNED', 'EVIDENCE_DISPUTED', 'DUPLICATE_DRAFT', 'OTHER')) then
            v_reason := 'Reason must be one of NOT_NEEDED, ALREADY_PLANNED, EVIDENCE_DISPUTED, DUPLICATE_DRAFT, OTHER.';
        elseif (P_REASON_CODE = 'OTHER' and (P_NOTE is null or length(trim(P_NOTE)) < 10)) then
            v_reason := 'OTHER needs a note of at least 10 characters.';
        elseif (v_n <> 1) then
            v_reason := 'No such draft.';
        elseif (v_status <> 'DRAFT') then
            v_reason := 'This draft is ' || v_status || ' and cannot be rejected.';
        end if;
        if (v_reason is not null) then
            v_outcome := 'REFUSED';
        end if;
    end if;

    begin transaction;
    insert into ACTION.AUD_ACTION (actor_user, actor_role, on_behalf_of, action_type, object_type, object_id,
                                   idempotency_key, outcome, reason, inputs, is_selftest)
    select :v_user, :v_role, :P_ON_BEHALF_OF, 'REJECT_WORK_ORDER_DRAFT', 'DRAFT', :P_DRAFT_ID,
           :P_IDEMPOTENCY_KEY, :v_outcome, :v_reason,
           object_construct('draft_id', :P_DRAFT_ID, 'reason_code', :P_REASON_CODE, 'note', :P_NOTE),
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
        select :v_id, 'WORK_ORDER_DRAFT', :P_DRAFT_ID, 'REJECT', :P_REASON_CODE, :P_NOTE,
               :v_user, :v_role, :P_ON_BEHALF_OF, current_timestamp()::timestamp_ntz,
               :P_IDEMPOTENCY_KEY, :v_selftest;
        update ACTION.ACT_WORK_ORDER_DRAFT set status = 'REJECTED' where draft_id = :P_DRAFT_ID;
        v_reason := 'Draft rejected (' || P_REASON_CODE || '). Recorded in the audit.';
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
