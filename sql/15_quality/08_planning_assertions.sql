-- =============================================================================
-- 15_quality / 08 — the plan is never invented                     STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : G4's "no plan is invented" (testing-and-validation.md)
-- Proves     : T-71 (GATING), T-31 (GATING), T-72, T-75, GS-3, no double-booking,
--              T-74 (accept/reject half, behavioural self-test)
-- Authority  : ADR-0018, CMP-9, docs/07-quality/testing-and-validation.md
-- Parameter  : <% database %>
--
-- T-31 re-derives every constraint from SOURCE (forecast, bookings, stock and
-- orders, certifications) rather than trusting the engine's own flag columns:
-- a check that reads the engine's answer back proves only that it agrees with
-- itself. T-71 is the anti-join ADR-0018 names.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-T71-FROM-ENGINE',      'T-71', 'G4', 'Every suggested window, crew and part is a feasible row the engine produced',
            'A schedule suggestion that invents a slot, a crew or a part', true),
        ('DQ-T31-FEASIBLE',         'T-31', 'G4', 'Every feasible candidate passes every constraint, re-derived from source',
            'A window offered as feasible that breaks weather, crew, part or crane limits', true),
        ('DQ-T72-BINDING',          'T-72', 'G4', 'Every elevated component is scheduled or carries a binding constraint; every date says what set it',
            'An empty answer, or a nearest-fit guess, when nothing is feasible', false),
        ('DQ-T75-IMPACT',           'T-75', 'G4', 'Suggestion impact reconciles exactly to the metric layer',
            'Plan impact figures that disagree with the numbers the rest of the app shows', false),
        ('DQ-GS3-BUNDLE',           'T-71', 'G4', 'At least one crane campaign bundles several jobs under one mobilisation, back to back',
            'A bundling claim with no bundle behind it', false),
        ('DQ-NO-DOUBLE-BOOKING',    'T-71', 'G4', 'No crew is suggested for two jobs on the same day',
            'A plan that is feasible job by job and impossible as a whole', true),
        ('DQ-T74-ACCEPT-REJECT',    'T-74', 'G4', 'Accept schedules drafts through the action service; repeat is DUPLICATE; invented, infeasible and undrafted suggestions are refused; reject needs a reason',
            'A schedule written outside the approval path, twice, or for a window the engine never produced', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_PLANNING_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id varchar;
    k      varchar;
    bad    integer;
    n      integer;
    d      varchar;
    sid    varchar;
    xsid   varchar;
    c1     varchar;
    c2     varchar;
    r      variant;
    r2     variant;
    r3     variant;
    r4     variant;
    r5     variant;
    r6     variant;
    n_sched integer;
    tot     number(38,0);
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');
    k := 'SELFTEST-' || :run_id || '-';

    -- T-71: anti-join every item against FEASIBLE candidate rows, matching the
    -- window, crew, part, component and dates. Zero rows or it fails.
    select count(*) into :bad
      from ENGINE.ENG_SUGGESTION_ITEM i
      join ENGINE.ENG_SUGGESTION s on s.suggestion_id = i.suggestion_id
     where (s.suggestion_type <> 'INFEASIBLE' and not exists (
               select 1 from ENGINE.ENG_WINDOW_CANDIDATE c
               where c.is_feasible and c.window_id = i.window_id and c.crew_id = i.crew_id
                 and c.part_number = i.part_number and c.component_id = i.component_id
                 and c.start_day = i.start_day and c.end_day = i.end_day))
        or (s.suggestion_type = 'INFEASIBLE' and i.window_id is not null);
    select count(*) into :n from ENGINE.ENG_SUGGESTION_ITEM;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T71-FROM-ENGINE', 'T-71', current_timestamp()::timestamp_ntz, :bad = 0 and :n > 0, :bad, 0,
           :n || ' suggestion items; ' || :bad || ' not matching a feasible engine row';

    -- T-31: re-derive every constraint from source for every feasible row.
    select count(*), listagg(distinct why, '; ') into :bad, :d from (
        select c.window_id,
               case
                   when (select count(*) from RAW.FCT_WIND_FORECAST f
                          where f.site_code = c.site_code and f.day between c.start_day and c.end_day
                            and f.forecast_max_gust_ms <= rp.max_gust_ms) <> rp.job_days          then 'weather'
                   when exists (select 1 from RAW.FCT_CRANE_BOOKING b
                                 where b.crew_id = c.crew_id and b.start_day <= c.end_day
                                   and b.end_day >= c.start_day)                                    then 'crew busy'
                   when not array_contains(rp.required_certification::variant, cr.certifications) then 'certification'
                   when not exists (select 1 from RAW.DIM_CREW_COVERAGE v
                                     where v.crew_id = c.crew_id and v.site_code = c.site_code)     then 'coverage'
                   when c.start_day < dateadd(day, rp.crane_mobilisation_days, c.plan_start)        then 'mobilisation'
                   when c.end_day > dateadd(day, 83, c.plan_start)                                  then 'horizon'
                   when c.start_day < c.part_available_date                                         then 'part date'
                   when c.part_available_date > c.plan_start
                        and c.part_available_date <> coalesce(
                            (select min(i.expected_date) from RAW.FCT_PART_INBOUND i
                              where i.part_number = c.part_number and i.expected_date = c.part_available_date),
                            dateadd(day, p.lead_time_days, c.plan_start))                           then 'part source'
               end as why
        from ENGINE.ENG_WINDOW_CANDIDATE c
        join RAW.DIM_REPAIR_PLAN rp on rp.component_class_code = c.component_class_code
        join RAW.DIM_PART p         on p.part_number = c.part_number
        join RAW.DIM_CREW cr        on cr.crew_id = c.crew_id
        where c.is_feasible
    ) where why is not null;
    select count(*), count_if(is_feasible) into :n, :n_sched from ENGINE.ENG_WINDOW_CANDIDATE;
    -- and the stored verdict must be the AND of the stored constraints
    select :bad + count_if(is_feasible <> (crew_certified and crew_available and weather_ok and part_available
                                           and mobilisation_ok and within_horizon))
      into :bad from ENGINE.ENG_WINDOW_CANDIDATE;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T31-FEASIBLE', 'T-31', current_timestamp()::timestamp_ntz, :bad = 0 and :n_sched > 0, :bad, 0,
           :n || ' candidates, ' || :n_sched || ' feasible; ' || :bad || ' violate a constraint re-derived from source'
           || coalesce(' (' || nullif(:d, '') || ')', '');

    -- T-72: every elevated component in exactly one suggestion; infeasible ones
    -- carry a binding constraint; every scheduled date says what set it.
    select count(*) into :bad from (
        select r.component_id
        from ENGINE.ENG_ALERT_RANKED r
        left join ENGINE.ENG_SUGGESTION_ITEM i on i.component_id = r.component_id
        where r.risk_band in ('HIGH', 'MEDIUM')
        group by r.component_id
        having count(i.suggestion_id) <> 1);
    select :bad + count_if(s.suggestion_type = 'INFEASIBLE' and (s.binding_constraint is null or length(s.binding_constraint) < 10))
                + count_if(s.suggestion_type <> 'INFEASIBLE' and i.earliest_limited_by is null),
           listagg(distinct iff(s.suggestion_type = 'INFEASIBLE', i.component_id || ': ' || s.binding_constraint, null), ' | ')
      into :bad, :d
      from ENGINE.ENG_SUGGESTION s join ENGINE.ENG_SUGGESTION_ITEM i on i.suggestion_id = s.suggestion_id;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T72-BINDING', 'T-72', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           :bad || ' gaps. Binding: ' || coalesce(:d, 'none infeasible');

    -- T-75: impact from the metric layer, exactly.
    select count_if(i.expected_loss_inr <> r.expected_loss_inr) into :bad
      from ENGINE.ENG_SUGGESTION_ITEM i join ENGINE.ENG_ALERT_RANKED r on r.component_id = i.component_id;
    select :bad + count_if(s.expected_loss_covered_inr <> iff(s.suggestion_type = 'INFEASIBLE', 0, x.loss)
                           or abs(s.planned_downtime_mwh - x.mwh) > 1e-6)
      into :bad
      from ENGINE.ENG_SUGGESTION s
      join (select suggestion_id, sum(expected_loss_inr) loss, sum(planned_downtime_mwh) mwh
            from ENGINE.ENG_SUGGESTION_ITEM group by 1) x on x.suggestion_id = s.suggestion_id;
    -- (a scalar subquery cannot sit in an INTO list, so the total is fetched first)
    select sum(expected_loss_inr) into :tot from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM');
    select :bad + iff(abs(p.covered_expected_loss_inr + p.uncovered_expected_loss_inr - :tot) < 1, 0, 1),
           'covered Rs ' || p.covered_expected_loss_inr || ', uncovered Rs ' || p.uncovered_expected_loss_inr
           || ', planned downtime ' || round(p.planned_downtime_mwh, 1) || ' MWh, crane mobilisations saved '
           || p.crane_mobilisations_saved
      into :bad, :d
      from ENGINE.ENG_PLAN_IMPACT p;
    -- planned downtime recomputed from the forecast and the power curve
    select :bad + count_if(abs(i.planned_downtime_mwh - x.mwh) > 1e-3) into :bad
      from ENGINE.ENG_SUGGESTION_ITEM i
      join (select i2.suggestion_id, i2.component_id,
                   sum(GEN.FN_EXPECTED_POWER(f.forecast_mean_wind_ms, pl.rated_power_mw * 1000, pl.cut_in_speed_ms,
                                             pl.rated_speed_ms, pl.cut_out_speed_ms)) * 24 / 1000 as mwh
            from ENGINE.ENG_SUGGESTION_ITEM i2
            join RAW.DIM_TURBINE t       on t.turbine_id = i2.turbine_id
            join RAW.DIM_PLATFORM pl     on pl.platform_id = t.platform_id
            join RAW.FCT_WIND_FORECAST f on f.site_code = t.site_code and f.day between i2.start_day and i2.end_day
            group by 1, 2) x
        on x.suggestion_id = i.suggestion_id and x.component_id = i.component_id;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T75-IMPACT', 'T-75', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           :bad || ' mismatches. ' || :d;

    -- GS-3: a real bundle — several jobs, one crew, back to back, no overlap.
    select count(*), max(site_code || ': ' || component_count || ' jobs with ' || crew_id || ', '
                         || to_varchar(start_day) || '..' || to_varchar(end_day))
      into :n, :d
      from ENGINE.ENG_SUGGESTION s
     where suggestion_type = 'BUNDLE' and component_count >= 2 and mobilisations_saved = component_count - 1
       and (select count(distinct crew_id) from ENGINE.ENG_SUGGESTION_ITEM i where i.suggestion_id = s.suggestion_id) = 1
       and (select count(*) from ENGINE.ENG_SUGGESTION_ITEM a join ENGINE.ENG_SUGGESTION_ITEM b
              on a.suggestion_id = b.suggestion_id and a.component_id < b.component_id
             where a.suggestion_id = s.suggestion_id
               and a.start_day <= b.end_day and a.end_day >= b.start_day) = 0;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-GS3-BUNDLE', 'T-71', current_timestamp()::timestamp_ntz, :n >= 1, :n, 1,
           :n || ' valid crane campaign(s)' || coalesce(': ' || :d, '');

    -- No crew in two places at once.
    select count(*) into :bad
      from ENGINE.ENG_SUGGESTION_ITEM a
      join ENGINE.ENG_SUGGESTION_ITEM b
        on a.crew_id = b.crew_id and a.component_id < b.component_id
       and a.start_day <= b.end_day and a.end_day >= b.start_day;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-NO-DOUBLE-BOOKING', 'T-71', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           :bad || ' overlapping crew assignments across suggestions';

    -- T-74, the accept/reject half, through the real procedures.
    select max(suggestion_id) into :sid from ENGINE.ENG_SUGGESTION where suggestion_type = 'BUNDLE';
    select max(suggestion_id) into :xsid from ENGINE.ENG_SUGGESTION where suggestion_type = 'INFEASIBLE';
    select min(component_id), max(component_id) into :c1, :c2 from ENGINE.ENG_SUGGESTION_ITEM where suggestion_id = :sid;
    call ACTION.SP_ACCEPT_SUGGESTION(:sid, :k || 'accept-nodraft', 'verify') into :r;       -- no drafts yet
    call ACTION.SP_DRAFT_WORK_ORDER(:c1, :k || 'pdraft1', 'verify') into :r2;
    call ACTION.SP_DRAFT_WORK_ORDER(:c2, :k || 'pdraft2', 'verify') into :r2;
    call ACTION.SP_ACCEPT_SUGGESTION(:sid, :k || 'accept', 'verify') into :r2;              -- applies
    call ACTION.SP_ACCEPT_SUGGESTION(:sid, :k || 'accept', 'verify') into :r3;              -- same key
    call ACTION.SP_ACCEPT_SUGGESTION('SG-S-INVENTED0000', :k || 'accept-invented', 'verify') into :r4;
    call ACTION.SP_ACCEPT_SUGGESTION(:xsid, :k || 'accept-infeasible', 'verify') into :r5;
    call ACTION.SP_REJECT_SUGGESTION(:sid, 'NOT_A_REASON', null, :k || 'reject-badreason', 'verify') into :r6;
    select count_if(window_status = 'SCHEDULED' and suggestion_id = :sid and window_id is not null)
      into :n_sched
      from ACTION.ACT_WORK_ORDER_DRAFT
     where is_selftest and component_id in (:c1, :c2) and idempotency_key like :k || 'pdraft%';
    select count(*) into :n from ACTION.AUD_ACTION
     where is_selftest and (idempotency_key like :k || 'accept%' or idempotency_key like :k || 'reject%');
    bad := iff(:r:outcome::varchar = 'REFUSED', 0, 1)
         + iff(:r2:outcome::varchar = 'APPLIED', 0, 1)
         + iff(:r3:outcome::varchar = 'DUPLICATE', 0, 1)
         + iff(:r4:outcome::varchar = 'REFUSED', 0, 1)
         + iff(:r5:outcome::varchar = 'REFUSED' or :xsid is null, 0, 1)
         + iff(:r6:outcome::varchar = 'REFUSED', 0, 1)
         + iff(:n_sched = 2, 0, 1)
         + iff(:n >= 6, 0, 1);
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T74-ACCEPT-REJECT', 'T-74', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           'no-draft ' || :r:outcome::varchar || '; accept ' || :r2:outcome::varchar || '; repeat ' || :r3:outcome::varchar
           || '; invented ' || :r4:outcome::varchar || '; infeasible ' || coalesce(:r5:outcome::varchar, 'n/a')
           || '; bad reason ' || :r6:outcome::varchar || '; drafts scheduled ' || :n_sched || '/2; audit rows ' || :n;

    -- close the self-test drafts so the next run can draft these components again
    let pat varchar := :k || 'pdraft%';
    let rs resultset := (select draft_id from ACTION.ACT_WORK_ORDER_DRAFT
                         where is_selftest and status = 'DRAFT' and idempotency_key like :pat);
    let cur cursor for rs;
    for rw in cur do
        let did varchar := rw.draft_id;
        call ACTION.SP_REJECT_WORK_ORDER_DRAFT(:did, 'OTHER', 'self-test: closing the planning drafts', :k || 'close-' || :did, 'verify');
    end for;

    return 'Planning quality run ' || :run_id || ' complete';
end;
$$;
