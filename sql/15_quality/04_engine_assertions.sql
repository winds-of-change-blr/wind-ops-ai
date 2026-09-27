-- =============================================================================
-- 15_quality / 04 — engine and serving assertions                STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the engine half of G4 and the funnel half of G5
-- Proves     : T-60 (GATING), T-61 (GATING), T-68 (GATING), T-70, T-86, I-13 guard
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
--
-- T-68 is three checks, because "evidence exists" is not enough on its own:
--   COVERAGE   the anti-join of incidents x the four channels returns zero
--   WELLFORMED every verdict is one of the three words, every detail non-empty
--   CONSISTENT no NUISANCE incident carries a SUPPORTS_ACTIONABLE verdict. If
--              it did, the stored evidence would contradict the class, and a
--              human reading it would be right to distrust both
--
-- T-61 is three checks too:
--   IN-QUEUE   every UNDETERMINED incident is in ENG_OPERATOR_QUEUE, ranked
--              below every ACTIONABLE one
--   RATE       the funnel publishes the rate and it reconciles to the table
--   (the third, NOT-HIDDEN, reads ACTION and so runs in 06_action_assertions)
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
            'I-13: a triage list where every component reads MINIMAL', false),
        ('DQ-T68-EVIDENCE-COVERAGE', 'T-68', 'G4', 'Every incident has a stored evidence row for each of the four channels',
            'A classification nobody can check, because the evidence it weighed was thrown away', true),
        ('DQ-T68-EVIDENCE-WELLFORMED','T-68', 'G4', 'Every evidence row has a known verdict and a readable detail',
            'Evidence rows that exist but say nothing', true),
        ('DQ-T68-EVIDENCE-CONSISTENT','T-68', 'G4', 'No NUISANCE incident carries evidence that supports ACTIONABLE',
            'Stored evidence that contradicts the class it is supposed to explain', true),
        ('DQ-T61-UNDETERMINED-QUEUED','T-61', 'G4', 'Every UNDETERMINED incident is in the operator queue, ranked below actionable',
            'Uncertainty quietly dropped from the queue, or ranked above what is known to matter', true),
        ('DQ-T61-RATE-PUBLISHED',    'T-61', 'G4', 'The undetermined rate is published and reconciles to the incident table',
            'A headline uncertainty figure that is missing, or does not match the data', true),
        ('DQ-I19-RISK-AGREES',       'T-29', 'G4', 'No NUISANCE incident on a turbine already scored MEDIUM or HIGH risk',
            'I-19: a classification that disagrees with the suppression guard (FR-32)', false)
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

    -- ---- T-68: evidence stored for every incident, every channel ----------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T68-EVIDENCE-COVERAGE', 'T-68', current_timestamp()::timestamp_ntz,
           missing = 0 and extra = 0, missing, 0,
           missing || ' (incident, channel) pairs with no evidence row; ' || extra
               || ' evidence rows for no incident; ' || n_inc || ' incidents x 4 channels'
    from (
        select
            (select count(*) from ENGINE.ENG_INCIDENT i
               cross join (select column1 as channel from values
                           ('CORROBORATION'), ('OPERATING_POINT'), ('RESET_RECURRENCE'), ('MODEL')) ch
               left join ENGINE.ENG_INCIDENT_EVIDENCE e
                 on e.incident_id = i.incident_id and e.channel = ch.channel
              where e.incident_id is null)                                        as missing,
            (select count(*) from ENGINE.ENG_INCIDENT_EVIDENCE e
              where not exists (select 1 from ENGINE.ENG_INCIDENT i
                                where i.incident_id = e.incident_id))            as extra,
            (select count(*) from ENGINE.ENG_INCIDENT)                           as n_inc
    );

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T68-EVIDENCE-WELLFORMED', 'T-68', current_timestamp()::timestamp_ntz,
           bad = 0 and dup = 0, bad + dup, 0,
           bad || ' rows with an unknown verdict or empty detail; ' || dup
               || ' duplicate (incident, channel) rows (primary keys are not enforced)'
    from (
        select
            count_if(verdict not in ('SUPPORTS_ACTIONABLE', 'SUPPORTS_NUISANCE', 'NO_EVIDENCE')
                     or trim(coalesce(detail, '')) = '')                         as bad,
            count(*) - count(distinct incident_id || '|' || channel)             as dup
        from ENGINE.ENG_INCIDENT_EVIDENCE
    );

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T68-EVIDENCE-CONSISTENT', 'T-68', current_timestamp()::timestamp_ntz,
           n = 0, n, 0,
           n || ' NUISANCE incidents with a SUPPORTS_ACTIONABLE or NO_EVIDENCE verdict on any channel'
    from (
        select count(distinct i.incident_id) as n
        from ENGINE.ENG_INCIDENT i
        join ENGINE.ENG_INCIDENT_EVIDENCE e on e.incident_id = i.incident_id
        where i.incident_class = 'NUISANCE'
          and e.verdict <> 'SUPPORTS_NUISANCE'
    );

    -- ---- T-61: UNDETERMINED never hidden, rate published -----------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T61-UNDETERMINED-QUEUED', 'T-61', current_timestamp()::timestamp_ntz,
           n_und > 0 and n_missing = 0 and coalesce(worst_act < best_und, n_act = 0),
           n_missing, 0,
           n_missing || ' of ' || n_und || ' UNDETERMINED incidents missing from ENG_OPERATOR_QUEUE; '
               || 'lowest-ranked actionable ' || coalesce(worst_act::varchar, 'n/a')
               || ', highest-ranked undetermined ' || coalesce(best_und::varchar, 'n/a')
    from (
        select
            (select count(*) from ENGINE.ENG_INCIDENT where incident_class = 'UNDETERMINED') as n_und,
            (select count(*) from ENGINE.ENG_INCIDENT where incident_class = 'ACTIONABLE')   as n_act,
            (select count(*) from ENGINE.ENG_INCIDENT i
              where i.incident_class = 'UNDETERMINED'
                and not exists (select 1 from ENGINE.ENG_OPERATOR_QUEUE q
                                where q.incident_id = i.incident_id))                  as n_missing,
            (select max(queue_rank) from ENGINE.ENG_OPERATOR_QUEUE where incident_class = 'ACTIONABLE')   as worst_act,
            (select min(queue_rank) from ENGINE.ENG_OPERATOR_QUEUE where incident_class = 'UNDETERMINED') as best_und
    );

    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T61-RATE-PUBLISHED', 'T-61', current_timestamp()::timestamp_ntz,
           f.undetermined_rate is not null and abs(f.undetermined_rate - t.rate) < 0.0001,
           f.undetermined_rate, t.rate,
           'published ' || coalesce(f.undetermined_rate::varchar, 'NULL') || ' in ENG_ALARM_FUNNEL; '
               || t.n_und || ' of ' || t.n || ' incidents = ' || round(t.rate, 4)
    from ENGINE.ENG_ALARM_FUNNEL f,
         (select count_if(incident_class = 'UNDETERMINED') as n_und, count(*) as n,
                 count_if(incident_class = 'UNDETERMINED') / nullif(count(*), 0) as rate
          from ENGINE.ENG_INCIDENT) t;

    -- I-19, read straight from the scores rather than from the evidence rows,
    -- so it does not share a derivation with the thing it checks.
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-I19-RISK-AGREES', 'T-29', current_timestamp()::timestamp_ntz,
           n = 0, n, 0,
           n || ' NUISANCE incidents on a turbine with a MEDIUM/HIGH score dated on or before the incident'
    from (
        select count(distinct i.incident_id) as n
        from ENGINE.ENG_INCIDENT i
        join ML.SCORE_COMPONENT_RISK s
          on s.turbine_id = i.turbine_id and s.scored_date <= i.incident_start::date
        where i.incident_class = 'NUISANCE' and s.risk_probability >= 0.30
    );

    return 'engine quality run ' || run_id || ' complete';
end;
$$;
