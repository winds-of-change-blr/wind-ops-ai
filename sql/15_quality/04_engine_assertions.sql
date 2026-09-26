-- =============================================================================
-- 15_quality / 04 — engine and serving assertions                STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the engine half of G4 and the funnel half of G5
-- Proves     : T-60 (GATING), T-70, T-86 (numbers), I-13 regression guard
-- Authority  : ADR-0017, AGENTS.md rule 3, docs/07-quality/testing-and-validation.md
-- Parameter  : <% database %>
--
-- DQ-NO-SUPPRESSED-FAILURE is the one that matters. Compression is trivially
-- achieved by calling everything nuisance; the only honest measure of an alarm
-- classifier is how many REAL failures it hid. The bound is zero and there is
-- no tolerance, because one hidden gearbox failure outweighs any compression
-- figure.
--
-- DQ-RISK-SURFACE is a regression guard for I-13: the published risk surface
-- must actually vary and must contain at least one component above p = 0.30.
-- Found by the T-18 degeneracy guard; asserted here so it cannot come back.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-NO-SUPPRESSED-FAILURE', 'T-60', 'G4', 'No real failure is hidden behind a nuisance classification',
            'A classifier that wins compression by suppressing the alarms that preceded a real failure', true),
        ('DQ-SAFETY-NEVER-NUISANCE', 'T-60', 'G4', 'No safety-critical code is ever classed nuisance',
            'Auto-suppressing a protection trip', false),
        ('DQ-FUNNEL-PAIRED',         'T-70', 'G4', 'Compression is never published without failures-suppressed beside it',
            'A headline number that improves as the system gets more dangerous', false),
        ('DQ-FUNNEL-POPULATED',      'T-86', 'G5', 'The funnel has real numbers at every stage',
            'An opening demo beat with nothing in it', false),
        ('DQ-RISK-SURFACE',          'T-14', 'G2', 'The published risk surface varies and has at least one elevated component',
            'I-13: a triage list where every component reads MINIMAL', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_ENGINE_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id varchar;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-NO-SUPPRESSED-FAILURE', 'T-60', current_timestamp()::timestamp_ntz,
           n = 0, n, 0,
           n || ' seeded failures were preceded, within 30 days, by an incident classed NUISANCE on the same component or turbine'
    from (select count(distinct failure_event_id) as n from ENGINE.ENG_SUPPRESSED_FAILURE);

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-SAFETY-NEVER-NUISANCE', 'T-60', current_timestamp()::timestamp_ntz,
           n = 0, n, 0,
           n || ' safety-critical incidents classed NUISANCE'
    from (select count(*) as n from ENGINE.ENG_INCIDENT where is_safety_critical and incident_class = 'NUISANCE');

    -- Structural check: the funnel view's column list must contain both.
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-FUNNEL-PAIRED', 'T-70', current_timestamp()::timestamp_ntz,
           n = 2, n, 2,
           n || ' of {COMPRESSION_RATIO, REAL_FAILURES_SUPPRESSED} present in ENG_ALARM_FUNNEL; both are required in the same view'
    from (select count(*) as n from information_schema.columns
          where table_schema = 'ENGINE' and table_name = 'ENG_ALARM_FUNNEL'
            and column_name in ('COMPRESSION_RATIO', 'REAL_FAILURES_SUPPRESSED'));

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-FUNNEL-POPULATED', 'T-86', current_timestamp()::timestamp_ntz,
           raw_alarms > 0 and incidents > 0 and actionable > 0 and incidents < raw_alarms,
           incidents, 1,
           raw_alarms || ' alarms -> ' || incidents || ' incidents -> ' || actionable || ' actionable, '
               || undetermined || ' undetermined, ' || nuisance || ' nuisance. Compression '
               || coalesce(compression_ratio::varchar, 'n/a') || ':1, real failures suppressed '
               || real_failures_suppressed || ', undetermined rate ' || coalesce(undetermined_rate::varchar, 'n/a')
    from ENGINE.ENG_ALARM_FUNNEL;

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-RISK-SURFACE', 'T-14', current_timestamp()::timestamp_ntz,
           coalesce(v > 0.0001 and n_elev > 0, false), n_elev, 1,
           n_elev || ' components at p >= 0.30 as of ' || coalesce(asof::varchar, 'n/a')
               || '; variance ' || coalesce(v::varchar, 'n/a') || ' (was 1e-12 before I-13)'
    from (select variance(risk_probability) as v, count_if(risk_probability >= 0.30) as n_elev,
                 max(scored_date) as asof
          from ML.SCORE_COMPONENT_RISK);

    return 'engine quality run ' || run_id || ' complete';
end;
$$;
