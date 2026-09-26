-- =============================================================================
-- 40_engine / 04 — schedule suggestions (CMP-18, ADR-0018)         STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-77 (suggestions only from engine windows), FR-78 (binding
--              constraint), FR-76/FR-80 (impact), GS-3 / VQ-8 (crane campaign)
-- Proves     : T-71 gating, T-72, T-75, GS-3 (15_quality/08)
-- Authority  : ADR-0018 ("selects, groups, ranks and explains ... cannot construct")
-- Parameter  : <% database %>
--
-- ===================== WHAT THIS LAYER MAY DO ================================
--
-- Pick FEASIBLE rows of ENG_WINDOW_CANDIDATE, group them, order them, explain
-- them. Every item a suggestion carries is a window_id copied from a feasible
-- candidate row, with that row's crew and part. T-71 anti-joins exactly that.
--
--   1. BUNDLE      crane jobs at one site that one crane team can do back to back
--                  in consecutive feasible windows: one mobilisation instead of
--                  N (GS-3). Highest expected loss first.
--   2. SCHEDULE    every other elevated component: its earliest feasible window
--                  whose crew is not already committed by an earlier suggestion.
--   3. INFEASIBLE  a component with no usable window gets its BINDING constraint
--                  (FR-78), taken from the rows of certified crews: the
--                  constraint that fails on every one of them, and when it
--                  clears. Never an empty answer, never a nearest-fit guess.
--
-- Each item also records what set its date (EARLIEST_LIMITED_BY): the
-- constraints that fail the day before, so "why not sooner?" has an answer.
--
-- Impact (T-75) is read, not computed: risk covered is the item's
-- ENG_ALERT_RANKED.expected_loss_inr; planned downtime energy is the power-curve
-- energy at FORECAST wind over the job days (the cost of doing the work).
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create table if not exists ENGINE.ENG_SUGGESTION (
    suggestion_id            varchar(40)   not null,
    suggestion_type          varchar(20)   not null,
    site_code                varchar(10)   not null,
    crew_id                  varchar(20),
    start_day                date,
    end_day                  date,
    component_count          integer       not null,
    mobilisations_saved      integer       not null,
    expected_loss_covered_inr number(38,0) not null,
    planned_downtime_mwh     float         not null,
    binding_constraint       varchar(500),
    reasoning                varchar(2000) not null,
    plan_start               date          not null,
    built_at                 timestamp_ntz not null,
    is_synthetic             boolean       not null default true,
    constraint pk_eng_suggestion primary key (suggestion_id)
) comment = 'Schedule suggestions drawn only from feasible ENG_WINDOW_CANDIDATE rows (FR-77): BUNDLE (one crane mobilisation for several jobs), SCHEDULE, or INFEASIBLE with the binding constraint (FR-78). Proposals only; acceptance is a human act through ACTION.SP_ACCEPT_SUGGESTION.';

create table if not exists ENGINE.ENG_SUGGESTION_ITEM (
    suggestion_id         varchar(40)  not null,
    component_id          varchar(30)  not null,
    turbine_id            varchar(20)  not null,
    window_id             varchar(40),
    crew_id               varchar(20),
    part_number           varchar(40)  not null,
    start_day             date,
    end_day               date,
    expected_loss_inr     number(38,0) not null,
    planned_downtime_mwh  float        not null,
    earliest_limited_by   varchar(500),
    is_synthetic          boolean      not null default true,
    constraint pk_eng_suggestion_item primary key (suggestion_id, component_id)
) comment = 'One row per component in a suggestion. WINDOW_ID/CREW_ID/PART_NUMBER come from a feasible candidate row (T-71); NULL window only for INFEASIBLE.';

create or replace procedure ENGINE.SP_BUILD_SUGGESTIONS()
returns varchar
language sql
execute as caller
as
$$
declare
    plan_start date;
    v_site  varchar;
    v_crew  varchar;
    v_n     integer;
    v_d     date;
    v_sid   varchar;
    v_comp  varchar;
    v_wid   varchar;
    v_s     date;
    v_e     date;
    n_b integer default 0;
    n_s integer default 0;
    n_i integer default 0;
    groups cursor for
        select site_code, crew_id, count(*) as n
        from (select component_id, site_code, crew_id, max(expected_loss_inr) as loss
              from ENGINE.ENG_WINDOW_CANDIDATE
              where is_feasible and requires_crane
              group by component_id, site_code, crew_id)
        group by site_code, crew_id
        having count(*) >= 2
        order by sum(loss) desc, site_code, crew_id;
    comps cursor for
        select distinct component_id, risk_rank from ENGINE.ENG_WINDOW_CANDIDATE order by risk_rank;
begin
    select min(plan_start) into :plan_start from ENGINE.ENG_WINDOW_CANDIDATE;
    delete from ENGINE.ENG_SUGGESTION_ITEM;
    delete from ENGINE.ENG_SUGGESTION;
    create or replace temporary table ENGINE.ENG_TMP_ASSIGN (crew_id varchar, start_day date, end_day date);

    -- ---- 1. crane-campaign bundles ------------------------------------------
    for g in groups do
        v_site := g.site_code;
        v_crew := g.crew_id;
        v_n    := g.n;
        -- members in risk order; each starts where the previous one ends
        create or replace temporary table ENGINE.ENG_TMP_MEMBER as
        select component_id, max(job_days) as job_days, min(risk_rank) as risk_rank,
               coalesce(sum(max(job_days)) over (order by min(risk_rank)
                        rows between unbounded preceding and 1 preceding), 0) as offset_days
        from ENGINE.ENG_WINDOW_CANDIDATE
        where site_code = :v_site and crew_id = :v_crew and is_feasible and requires_crane
          and component_id not in (select component_id from ENGINE.ENG_SUGGESTION_ITEM)
        group by component_id;
        select count(*) into :v_n from ENGINE.ENG_TMP_MEMBER;

        v_d := null;
        if (v_n >= 2) then
            select min(d) into :v_d from (
                select dateadd(day, -m.offset_days, c.start_day) as d, count(distinct c.component_id) as k
                from ENGINE.ENG_WINDOW_CANDIDATE c
                join ENGINE.ENG_TMP_MEMBER m on m.component_id = c.component_id
                where c.crew_id = :v_crew and c.is_feasible
                  and not exists (select 1 from ENGINE.ENG_TMP_ASSIGN a
                                  where a.crew_id = c.crew_id and a.start_day <= c.end_day and a.end_day >= c.start_day)
                group by 1
            ) where k = :v_n;
        end if;

        if (v_d is not null) then
            v_sid := 'SG-B-' || substr(sha2(:v_site || :v_crew || to_varchar(:v_d)), 1, 12);
            insert into ENGINE.ENG_SUGGESTION_ITEM (suggestion_id, component_id, turbine_id, window_id, crew_id,
                                                    part_number, start_day, end_day, expected_loss_inr, planned_downtime_mwh)
            select :v_sid, c.component_id, c.turbine_id, c.window_id, c.crew_id, c.part_number,
                   c.start_day, c.end_day, c.expected_loss_inr, 0
            from ENGINE.ENG_WINDOW_CANDIDATE c
            join ENGINE.ENG_TMP_MEMBER m on m.component_id = c.component_id
            where c.crew_id = :v_crew and c.is_feasible
              and c.start_day = dateadd(day, m.offset_days, :v_d);
            insert into ENGINE.ENG_TMP_ASSIGN
            select :v_crew, min(start_day), max(end_day) from ENGINE.ENG_SUGGESTION_ITEM where suggestion_id = :v_sid;
            insert into ENGINE.ENG_SUGGESTION (suggestion_id, suggestion_type, site_code, crew_id, start_day, end_day,
                                               component_count, mobilisations_saved, expected_loss_covered_inr,
                                               planned_downtime_mwh, reasoning, plan_start, built_at)
            select :v_sid, 'BUNDLE', :v_site, :v_crew, min(start_day), max(end_day), count(*), count(*) - 1,
                   sum(expected_loss_inr), 0,
                   'Crane campaign at ' || :v_site || ': ' || count(*) || ' crane jobs ('
                   || listagg(component_id, ', ') within group (order by start_day)
                   || ') back to back with ' || :v_crew || ', ' || to_varchar(min(start_day)) || ' to '
                   || to_varchar(max(end_day)) || '. One crane mobilisation instead of ' || count(*)
                   || '. Every job window passed all six constraints.',
                   :plan_start, current_timestamp()::timestamp_ntz
            from ENGINE.ENG_SUGGESTION_ITEM where suggestion_id = :v_sid;
            n_b := n_b + 1;
        end if;
    end for;

    -- ---- 2. single jobs, in risk order, without double-booking a crew --------
    for c in comps do
        v_comp := c.component_id;
        select count(*) into :v_n from ENGINE.ENG_SUGGESTION_ITEM where component_id = :v_comp;
        if (v_n = 0) then
            v_wid := null;
            select max(window_id), max(crew_id), max(start_day), max(end_day)
              into :v_wid, :v_crew, :v_s, :v_e
              from (select w.window_id, w.crew_id, w.start_day, w.end_day
                    from ENGINE.ENG_WINDOW_CANDIDATE w
                    where w.component_id = :v_comp and w.is_feasible
                      and not exists (select 1 from ENGINE.ENG_TMP_ASSIGN a
                                      where a.crew_id = w.crew_id and a.start_day <= w.end_day and a.end_day >= w.start_day)
                    order by w.start_day, w.requires_crane, w.crew_id
                    limit 1);
            if (v_wid is not null) then
                v_sid := 'SG-S-' || substr(sha2(:v_wid), 1, 12);
                insert into ENGINE.ENG_SUGGESTION_ITEM (suggestion_id, component_id, turbine_id, window_id, crew_id,
                                                        part_number, start_day, end_day, expected_loss_inr, planned_downtime_mwh)
                select :v_sid, component_id, turbine_id, window_id, crew_id, part_number, start_day, end_day,
                       expected_loss_inr, 0
                from ENGINE.ENG_WINDOW_CANDIDATE where window_id = :v_wid;
                insert into ENGINE.ENG_TMP_ASSIGN values (:v_crew, :v_s, :v_e);
                insert into ENGINE.ENG_SUGGESTION (suggestion_id, suggestion_type, site_code, crew_id, start_day, end_day,
                                                   component_count, mobilisations_saved, expected_loss_covered_inr,
                                                   planned_downtime_mwh, reasoning, plan_start, built_at)
                select :v_sid, 'SCHEDULE', site_code, crew_id, start_day, end_day, 1, 0, expected_loss_inr, 0,
                       'Earliest feasible window for ' || component_id || ': ' || to_varchar(start_day) || ' to '
                       || to_varchar(end_day) || ' with ' || crew_id || iff(requires_crane, ' (crane job)', '')
                       || '. Part ' || part_number || ': ' || part_source || '.',
                       :plan_start, current_timestamp()::timestamp_ntz
                from ENGINE.ENG_WINDOW_CANDIDATE where window_id = :v_wid;
                n_s := n_s + 1;
            end if;
        end if;
    end for;

    -- ---- 3. no usable window: the binding constraint --------------------------
    -- Judged over CERTIFIED crews only; an uncertified crew's windows would
    -- otherwise make "certification" look binding for every crane job.
    insert into ENGINE.ENG_SUGGESTION_ITEM (suggestion_id, component_id, turbine_id, window_id, crew_id,
                                            part_number, start_day, end_day, expected_loss_inr, planned_downtime_mwh)
    select 'SG-X-' || substr(sha2(component_id), 1, 12), component_id, max(turbine_id), null, null,
           max(part_number), null, null, max(expected_loss_inr), 0
    from ENGINE.ENG_WINDOW_CANDIDATE
    where component_id not in (select component_id from ENGINE.ENG_SUGGESTION_ITEM)
    group by component_id;

    insert into ENGINE.ENG_SUGGESTION (suggestion_id, suggestion_type, site_code, crew_id, start_day, end_day,
                                       component_count, mobilisations_saved, expected_loss_covered_inr,
                                       planned_downtime_mwh, binding_constraint, reasoning, plan_start, built_at)
    with cand as (
        select c.*, count_if(c.crew_certified) over (partition by c.component_id) as n_cert_rows
        from ENGINE.ENG_WINDOW_CANDIDATE c
        where c.component_id in (select component_id from ENGINE.ENG_SUGGESTION_ITEM where window_id is null)
    ),
    b as (
        select component_id, max(site_code) as site_code, max(part_number) as part_number,
               max(part_available_date) as part_date, max(part_source) as part_source, max(plan_start) as ps,
               max(n_cert_rows) as n_cert,
               booland_agg(not part_available)  as all_part,
               booland_agg(not mobilisation_ok) as all_mob,
               booland_agg(not crew_available)  as all_busy,
               booland_agg(not weather_ok)      as all_wx,
               booland_agg(not within_horizon)  as all_hor
        from cand
        where crew_certified or n_cert_rows = 0
        group by component_id
    )
    select 'SG-X-' || substr(sha2(component_id), 1, 12), 'INFEASIBLE', site_code, null, null, null, 1, 0, 0, 0,
           case
               when n_cert = 0   then 'No certified crew covers ' || site_code || ' for this repair'
               when all_part     then 'Part ' || part_number || ' not available until ' || to_varchar(part_date)
                                      || ' (' || part_source || '), after the 12-week horizon ends '
                                      || to_varchar(dateadd(day, 83, ps))
               when all_busy     then 'Every certified crew is committed throughout the horizon'
               when all_wx       then 'No run of workable-wind days in the 12-week forecast'
               when all_mob      then 'Crane cannot be mobilised inside the horizon'
               else 'No single constraint; no day satisfies all six together'
           end,
           'No feasible window for ' || component_id || ' in the 12-week horizon. Reported as infeasible rather than '
           || 'offered a nearest fit (ADR-0018 rule 3).',
           :plan_start, current_timestamp()::timestamp_ntz
    from b;
    n_i := sqlrowcount;

    -- ---- what set each date, and the impact figures --------------------------
    update ENGINE.ENG_SUGGESTION_ITEM i
       set earliest_limited_by = x.why
      from (
        select i2.suggestion_id, i2.component_id,
               case
                   when i2.start_day = p.plan_start then 'nothing: the first day of the horizon'
                   when prev.window_id is null      then 'the start of the horizon'
                   when prev.is_feasible            then 'the crew''s other commitments in this plan'
                   else array_to_string(array_construct_compact(
                            iff(not prev.part_available,  'part (' || prev.part_source || ')', null),
                            iff(not prev.mobilisation_ok, 'crane mobilisation lead time', null),
                            iff(not prev.crew_available,  'crew committed: ' || prev.crew_conflict, null),
                            iff(not prev.weather_ok,      'forecast gust ' || round(prev.max_forecast_gust_ms, 1)
                                                          || ' m/s above the ' || prev.gust_limit_ms || ' m/s limit', null)), '; ')
               end as why
        from ENGINE.ENG_SUGGESTION_ITEM i2
        join ENGINE.ENG_WINDOW_CANDIDATE p on p.window_id = i2.window_id
        left join ENGINE.ENG_WINDOW_CANDIDATE prev
               on prev.component_id = p.component_id and prev.crew_id = p.crew_id
              and prev.start_day = dateadd(day, -1, p.start_day)
      ) x
     where i.suggestion_id = x.suggestion_id and i.component_id = x.component_id;

    update ENGINE.ENG_SUGGESTION_ITEM i
       set planned_downtime_mwh = x.mwh
      from (
        select i2.suggestion_id, i2.component_id,
               round(sum(GEN.FN_EXPECTED_POWER(f.forecast_mean_wind_ms, pl.rated_power_mw * 1000,
                         pl.cut_in_speed_ms, pl.rated_speed_ms, pl.cut_out_speed_ms)) * 24 / 1000, 3) as mwh
        from ENGINE.ENG_SUGGESTION_ITEM i2
        join RAW.DIM_TURBINE t        on t.turbine_id = i2.turbine_id
        join RAW.DIM_PLATFORM pl      on pl.platform_id = t.platform_id
        join RAW.FCT_WIND_FORECAST f  on f.site_code = t.site_code and f.day between i2.start_day and i2.end_day
        group by i2.suggestion_id, i2.component_id
      ) x
     where i.suggestion_id = x.suggestion_id and i.component_id = x.component_id;

    update ENGINE.ENG_SUGGESTION s
       set planned_downtime_mwh = x.mwh
      from (select suggestion_id, sum(planned_downtime_mwh) as mwh from ENGINE.ENG_SUGGESTION_ITEM group by 1) x
     where s.suggestion_id = x.suggestion_id;

    return n_b || ' bundle(s), ' || n_s || ' single job(s), ' || n_i || ' infeasible';
end;
$$;

-- The plan's effect before anyone commits to it (FR-80): what the suggestions
-- cover, what they leave uncovered, and what the work itself costs in energy.
create or replace view ENGINE.ENG_PLAN_IMPACT as
select
    (select sum(expected_loss_inr) from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM'))   as elevated_expected_loss_inr,
    sum(iff(suggestion_type <> 'INFEASIBLE', expected_loss_covered_inr, 0))                             as covered_expected_loss_inr,
    (select sum(expected_loss_inr) from ENGINE.ENG_ALERT_RANKED where risk_band in ('HIGH', 'MEDIUM'))
      - sum(iff(suggestion_type <> 'INFEASIBLE', expected_loss_covered_inr, 0))                         as uncovered_expected_loss_inr,
    sum(planned_downtime_mwh)                                                                          as planned_downtime_mwh,
    sum(mobilisations_saved)                                                                           as crane_mobilisations_saved,
    count_if(suggestion_type = 'INFEASIBLE')                                                           as infeasible_components,
    true                                                                                               as is_synthetic
from ENGINE.ENG_SUGGESTION;
