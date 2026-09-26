-- =============================================================================
-- 15_quality / 06 — G4 action assertions: guards, audit, grants    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the approval half of G4 (M10)
-- Proves     : T-29 (GATING), T-30, T-33 (GATING, grant half), T-34, T-35 (GATING),
--              T-76 (grant half), FR-34 procedure reference
-- Authority  : ADR-0005, docs/07-quality/testing-and-validation.md
-- Parameter  : <% database %>
--
-- These are BEHAVIOURAL tests: they call the real procedures and read what
-- happened, rather than reading the procedure source. A guard that exists in
-- the code but not in the behaviour is the failure mode being tested for.
--
-- They leave rows, marked IS_SELFTEST, because ACTION is append-only and a
-- test that deleted its own evidence would disprove the property it tests.
--
-- T-35 needs an audit failure on demand, which is what OPS.OPS_TEST_HOOK is
-- for. The hook is switched on for exactly one call and off again, and
-- DQ-FAULT-HOOK-OFF fails the build if it is ever left on.
--
-- T-33's other half — a direct INSERT attempted AS WOA_APP and AS WOA_AGENT —
-- cannot run here, because a procedure cannot change role. It runs from the
-- recipe (`just verify`) as two sessions that must each be refused.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-T29-SAFETY',              'T-29', 'G4', 'A safety-critical alarm cannot be suppressed',
            'A protection trip hidden from the control room', true),
        ('DQ-T29-ELEVATED',            'T-29', 'G4', 'An alarm on an asset with elevated evidence cannot be suppressed',
            'Hiding the one alarm that corroborates a developing failure', true),
        ('DQ-T29-RISK',                'T-29', 'G4', 'An alarm on a turbine with MEDIUM or HIGH risk cannot be suppressed',
            'Suppressing on an asset the model already says is failing (FR-32)', true),
        ('DQ-T29-UNDETERMINED',        'T-29', 'G4', 'An UNDETERMINED incident cannot be suppressed',
            'Hiding what the engine explicitly left for a human', false),
        ('DQ-T30-REVERSIBLE',          'T-30', 'G4', 'A suppression is time-boxed, reversible and audited, and never deleted',
            'A suppression nobody can undo or reconstruct', false),
        ('DQ-T34-IDEMPOTENT',          'T-34', 'G4', 'Approving the same draft twice creates exactly one work order',
            'A double-click that books two crane campaigns', false),
        ('DQ-T35-AUDIT-BLOCKS',        'T-35', 'G4', 'When the audit append fails, nothing is written',
            'An unaudited state change', true),
        ('DQ-EVERY-WRITE-AUDITED',     'T-35', 'G4', 'Every ACTION row has an APPLIED audit row written no later than it',
            'A write path that skips the audit', false),
        ('DQ-ACTION-NO-DIRECT-GRANT',  'T-33', 'G4', 'No role holds a write privilege on an ACTION table; no future grants in ACTION',
            'A role that can write around the approval procedures', true),
        ('DQ-T76-NO-ACTION-PRIV',      'T-76', 'G4', 'WOA_SCHEDULER and WOA_AGENT hold nothing on ACTION',
            'An automation or agent that can apply, not just propose', true),
        ('DQ-FAULT-HOOK-OFF',          'T-35', 'G4', 'The audit fault-injection hook is off',
            'A test switch left on in a live system', true),
        ('DQ-DRAFT-PROCEDURE-RESOLVES','T-32', 'G4', 'Every part of a scored component class maps to a procedure document that was parsed',
            'A work order citing a procedure that does not exist', false),
        -- T-61's third leg lives here, not in the engine suite: it reads ACTION,
        -- which deploy-engine's gate runs before.
        ('DQ-T61-NEVER-SUPPRESSED',    'T-61', 'G4', 'No UNDETERMINED incident is under an active suppression',
            'Hiding what the system does not understand', true)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_ACTION_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id   varchar;
    k        varchar;
    r        variant;
    r2       variant;
    r3       variant;
    inc      varchar;
    comp1    varchar;
    comp2    varchar;
    d1       varchar;
    d2       varchar;
    sid      varchar;
    n        integer;
    n2       integer;
    bad      integer default 0;
    raised   boolean default false;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');
    k := 'SELFTEST-' || :run_id || '-';

    -- T-29a: safety-critical
    select min(incident_id) into :inc from ENGINE.ENG_INCIDENT where is_safety_critical;
    call ACTION.SP_APPROVE_SUPPRESSION(:inc, 24, 'self-test: safety guard', :k || 'safety', 'verify') into :r;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T29-SAFETY', 'T-29', current_timestamp()::timestamp_ntz,
           :inc is not null and :r:outcome::varchar = 'REFUSED', iff(:r:outcome::varchar = 'REFUSED', 0, 1), 0,
           coalesce(:inc, 'no safety-critical incident in the data') || ' -> ' || coalesce(:r:outcome::varchar, 'null')
           || ': ' || coalesce(:r:message::varchar, '');

    -- T-29b: elevated evidence
    select min(incident_id) into :inc from ENGINE.ENG_INCIDENT where is_elevated and not is_safety_critical;
    call ACTION.SP_APPROVE_SUPPRESSION(:inc, 24, 'self-test: elevated guard', :k || 'elevated', 'verify') into :r;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T29-ELEVATED', 'T-29', current_timestamp()::timestamp_ntz,
           :inc is not null and :r:outcome::varchar = 'REFUSED', iff(:r:outcome::varchar = 'REFUSED', 0, 1), 0,
           coalesce(:inc, 'no elevated incident') || ' -> ' || coalesce(:r:outcome::varchar, 'null')
           || ': ' || coalesce(:r:message::varchar, '');

    -- T-29c: a NUISANCE incident on a turbine at MEDIUM/HIGH risk — the case the
    -- engine's is_elevated flag does not cover, and FR-32 does.
    select min(i.incident_id) into :inc from ENGINE.ENG_INCIDENT i
     where i.incident_class = 'NUISANCE' and not i.is_safety_critical and not i.is_elevated
       and i.turbine_id in (select turbine_id from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM'));
    if (inc is null) then
        -- No natural case: use any incident on a risky turbine. The risk guard
        -- runs before the class check, so it must still be the refusal given.
        select min(i.incident_id) into :inc from ENGINE.ENG_INCIDENT i
         where not i.is_safety_critical and not i.is_elevated
           and i.turbine_id in (select turbine_id from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM'));
    end if;
    call ACTION.SP_APPROVE_SUPPRESSION(:inc, 24, 'self-test: risk guard', :k || 'risk', 'verify') into :r;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T29-RISK', 'T-29', current_timestamp()::timestamp_ntz,
           :inc is not null and :r:outcome::varchar = 'REFUSED' and contains(:r:message::varchar, 'failure risk'),
           iff(:r:outcome::varchar = 'REFUSED', 0, 1), 0,
           coalesce(:inc, 'no incident on a risky turbine') || ' -> ' || coalesce(:r:outcome::varchar, 'null')
           || ': ' || coalesce(:r:message::varchar, '');

    -- T-29d: UNDETERMINED on a clean turbine
    select min(i.incident_id) into :inc from ENGINE.ENG_INCIDENT i
     where i.incident_class = 'UNDETERMINED' and not i.is_safety_critical and not i.is_elevated
       and i.turbine_id not in (select turbine_id from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM'));
    call ACTION.SP_APPROVE_SUPPRESSION(:inc, 24, 'self-test: undetermined guard', :k || 'undetermined', 'verify') into :r;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T29-UNDETERMINED', 'T-29', current_timestamp()::timestamp_ntz,
           :inc is not null and :r:outcome::varchar = 'REFUSED', iff(:r:outcome::varchar = 'REFUSED', 0, 1), 0,
           coalesce(:inc, 'no clean undetermined incident') || ' -> ' || coalesce(:r:outcome::varchar, 'null')
           || ': ' || coalesce(:r:message::varchar, '');

    -- T-30: suppress an eligible incident, then revoke; nothing deleted.
    select min(i.incident_id) into :inc from ENGINE.ENG_INCIDENT i
     where i.incident_class = 'NUISANCE' and not i.is_safety_critical and not i.is_elevated
       and i.turbine_id not in (select turbine_id from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM'));
    call ACTION.SP_APPROVE_SUPPRESSION(:inc, 24, 'self-test: reversible suppression', :k || 'suppress', 'verify') into :r;
    sid := r:suppression_id::varchar;
    call ACTION.SP_REVOKE_SUPPRESSION(:sid, 'self-test: revoke it again', :k || 'revoke', 'verify') into :r2;
    select count(*) into :n from ACTION.ACT_SUPPRESSION
     where suppression_id = :sid and status = 'REVOKED'
       and expires_at <= dateadd(hour, 168, approved_at) and revoked_at is not null;
    select count(*) into :n2 from ACTION.AUD_ACTION
     where idempotency_key in (:k || 'suppress', :k || 'revoke') and outcome = 'APPLIED';
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T30-REVERSIBLE', 'T-30', current_timestamp()::timestamp_ntz,
           :r:outcome::varchar = 'APPLIED' and :r2:outcome::varchar = 'APPLIED' and :n = 1 and :n2 = 2,
           2 - :n2, 0,
           coalesce(:inc, 'no eligible incident') || ': suppress ' || coalesce(:r:outcome::varchar, 'null')
           || ', revoke ' || coalesce(:r2:outcome::varchar, 'null') || '; row kept as REVOKED: ' || :n
           || '; applied audit rows: ' || :n2;

    -- T-34: draft the top-ranked component, approve three times.
    select component_id into :comp1 from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM')
     order by money_rank limit 1;
    call ACTION.SP_DRAFT_WORK_ORDER(:comp1, :k || 'draft1', 'verify') into :r;
    d1 := r:draft_id::varchar;
    call ACTION.SP_APPROVE_WORK_ORDER(:d1, :k || 'approve1', 'verify') into :r;
    call ACTION.SP_APPROVE_WORK_ORDER(:d1, :k || 'approve1', 'verify') into :r2;
    call ACTION.SP_APPROVE_WORK_ORDER(:d1, :k || 'approve1-other-key', 'verify') into :r3;
    select count(*) into :n from ACTION.ACT_WORK_ORDER where draft_id = :d1;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T34-IDEMPOTENT', 'T-34', current_timestamp()::timestamp_ntz,
           :n = 1 and :r:outcome::varchar = 'APPLIED' and :r2:outcome::varchar = 'DUPLICATE'
             and :r3:outcome::varchar = 'DUPLICATE',
           :n, 1,
           coalesce(:comp1, 'no ranked component') || ' draft ' || coalesce(:d1, 'none') || ': approvals '
           || coalesce(:r:outcome::varchar, 'null') || ' / ' || coalesce(:r2:outcome::varchar, 'null')
           || ' (same key) / ' || coalesce(:r3:outcome::varchar, 'null') || ' (new key); work orders: ' || :n;

    -- T-35: force the audit to fail on an approval; nothing may be written.
    select component_id into :comp2 from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM')
     order by money_rank limit 1 offset 1;
    call ACTION.SP_DRAFT_WORK_ORDER(:comp2, :k || 'draft2', 'verify') into :r;
    d2 := r:draft_id::varchar;
    update OPS.OPS_TEST_HOOK set enabled = true, set_at = current_timestamp()::timestamp_ntz where hook = 'FAIL_AUDIT';
    begin
        call ACTION.SP_APPROVE_WORK_ORDER(:d2, :k || 'approve2', 'verify') into :r2;
        raised := false;
    exception
        when other then
            raised := true;
    end;
    update OPS.OPS_TEST_HOOK set enabled = false, set_at = current_timestamp()::timestamp_ntz where hook = 'FAIL_AUDIT';
    select count(*) into :n from ACTION.ACT_WORK_ORDER where draft_id = :d2;
    select count(*) into :n2 from ACTION.AUD_ACTION where idempotency_key = :k || 'approve2';
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T35-AUDIT-BLOCKS', 'T-35', current_timestamp()::timestamp_ntz,
           :d2 is not null and :raised and :n = 0 and :n2 = 0, :n + :n2, 0,
           'draft ' || coalesce(:d2, 'none') || ': approval raised=' || :raised || '; work orders written: ' || :n
           || '; audit rows left behind: ' || :n2;
    -- Close the test draft so the next run can draft this component again.
    call ACTION.SP_REJECT_WORK_ORDER_DRAFT(:d2, 'OTHER', 'self-test: closing the T-35 draft', :k || 'reject2', 'verify') into :r;

    -- Every state-bearing row has an APPLIED audit row, no later than itself.
    select count(*) into :n from (
        select s.idempotency_key, s.approved_at as at from ACTION.ACT_SUPPRESSION s
        union all select w.idempotency_key, w.approved_at from ACTION.ACT_WORK_ORDER w
        union all select d.idempotency_key, d.drafted_at from ACTION.ACT_WORK_ORDER_DRAFT d
        union all select c.idempotency_key, c.decided_at from ACTION.ACT_DECISION c
    ) w
    where not exists (select 1 from ACTION.AUD_ACTION a
                       where a.idempotency_key = w.idempotency_key and a.outcome = 'APPLIED' and a.event_at <= w.at);
    select count(*) into :n2 from (
        select idempotency_key from ACTION.ACT_SUPPRESSION union all select idempotency_key from ACTION.ACT_WORK_ORDER
        union all select idempotency_key from ACTION.ACT_WORK_ORDER_DRAFT union all select idempotency_key from ACTION.ACT_DECISION);
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-EVERY-WRITE-AUDITED', 'T-35', current_timestamp()::timestamp_ntz,
           :n = 0 and :n2 > 0, :n, 0, :n2 || ' ACTION rows; ' || :n || ' without an earlier APPLIED audit row';

    -- T-33 grant half: nothing beyond OWNERSHIP and SELECT on any ACTION object,
    -- and no future grants scoped to ACTION. SELECT is tolerated because it
    -- cannot write: in dev it reaches WOA_ENGINEER through 12_grants_dev's
    -- database-wide future grant, which is how engineers read the audit.
    bad := 0;
    show grants on table ACTION.AUD_ACTION;
    select count(*) into :n from table(result_scan(last_query_id())) where "privilege" not in ('OWNERSHIP', 'SELECT');
    bad := bad + n;
    show grants on table ACTION.ACT_SUPPRESSION;
    select count(*) into :n from table(result_scan(last_query_id())) where "privilege" not in ('OWNERSHIP', 'SELECT');
    bad := bad + n;
    show grants on table ACTION.ACT_WORK_ORDER_DRAFT;
    select count(*) into :n from table(result_scan(last_query_id())) where "privilege" not in ('OWNERSHIP', 'SELECT');
    bad := bad + n;
    show grants on table ACTION.ACT_WORK_ORDER;
    select count(*) into :n from table(result_scan(last_query_id())) where "privilege" not in ('OWNERSHIP', 'SELECT');
    bad := bad + n;
    show grants on table ACTION.ACT_DECISION;
    select count(*) into :n from table(result_scan(last_query_id())) where "privilege" not in ('OWNERSHIP', 'SELECT');
    bad := bad + n;
    show grants on view ACTION.ACT_V_SUPPRESSION_ACTIVE;
    select count(*) into :n from table(result_scan(last_query_id())) where "privilege" not in ('OWNERSHIP', 'SELECT');
    bad := bad + n;
    show future grants in schema ACTION;
    select count(*) into :n from table(result_scan(last_query_id()));
    bad := bad + n;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-ACTION-NO-DIRECT-GRANT', 'T-33', current_timestamp()::timestamp_ntz,
           :bad = 0, :bad, 0, :bad || ' write-capable or ACTION-scoped future grants on ACTION tables and views';

    -- T-76 grant half: the scheduler and the agent hold nothing on ACTION.
    bad := 0;
    show grants to role WOA_SCHEDULER;
    select count(*) into :n from table(result_scan(last_query_id()))
     where "name" ilike '%.ACTION' or "name" ilike '%.ACTION.%';
    bad := bad + n;
    show grants to role WOA_AGENT;
    select count(*) into :n from table(result_scan(last_query_id()))
     where "name" ilike '%.ACTION' or "name" ilike '%.ACTION.%';
    bad := bad + n;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T76-NO-ACTION-PRIV', 'T-76', current_timestamp()::timestamp_ntz,
           :bad = 0, :bad, 0, :bad || ' grants on ACTION held by WOA_SCHEDULER or WOA_AGENT';

    select count_if(enabled) into :n from OPS.OPS_TEST_HOOK;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-FAULT-HOOK-OFF', 'T-35', current_timestamp()::timestamp_ntz,
           :n = 0, :n, 0, :n || ' fault hooks enabled';

    select count(*) into :n from RAW.DIM_PART p
     where p.component_class_code in (select distinct component_class_code from ENGINE.ENG_ALERT_RANKED)
       and not exists (select 1 from DOCS.DOC_PART_PROCEDURE m
                        join DOCS.DOC_PARSED d on d.doc_id = m.doc_id
                       where m.part_number = p.part_number);
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-DRAFT-PROCEDURE-RESOLVES', 'T-32', current_timestamp()::timestamp_ntz,
           :n = 0, :n, 0, :n || ' parts of scored component classes with no parsed procedure document';

    select count(*) into :n
      from ACTION.ACT_V_SUPPRESSION_ACTIVE s
      join ENGINE.ENG_INCIDENT i on i.incident_id = s.incident_id
     where i.incident_class = 'UNDETERMINED';
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T61-NEVER-SUPPRESSED', 'T-61', current_timestamp()::timestamp_ntz,
           :n = 0, :n, 0, :n || ' UNDETERMINED incidents under an active suppression';

    return 'Action quality run ' || :run_id || ' complete';
end;
$$;
