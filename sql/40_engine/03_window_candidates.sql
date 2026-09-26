-- =============================================================================
-- 40_engine / 03 — candidate maintenance windows (CMP-9)           STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-33 (windows satisfying every constraint), FR-38 (part and lead
--              time shown), FR-78's input (which constraint failed)
-- Proves     : T-31 (15_quality/08): every feasible row passes every constraint,
--              re-checked from source
-- Authority  : docs/03-architecture/03-component.md CMP-9, ADR-0018, data-model.md §6
-- Parameter  : <% database %>
--
-- ===================== HARD FILTERS, KEPT WITH THEIR REASONS ==================
--
-- One row per (elevated component x crew able to reach the site x start day in a
-- rolling 12-week horizon). Every constraint is its own boolean column with its
-- own detail, and IS_FEASIBLE is their AND. Nothing is weighted: a window that
-- fails a constraint is infeasible, never "less preferred" (CMP-9).
--
-- Infeasible rows are KEPT. A planner needs to know WHICH constraint excluded a
-- window — "no crane team free" and "bearing arrives too late" lead to different
-- actions (data-model §6) — and the suggestion layer reports the binding
-- constraint from them (FR-78). Suggestions select only feasible rows (T-71).
--
--   crew_certified   the crew holds the repair plan's required certification
--   crew_available   no existing commitment overlaps the job days
--   weather_ok       every job day is forecast within the job's gust limit
--   part_available   the part is in hand by the start day: stock and open orders
--                    are allocated to jobs in order of expected loss, and a job
--                    beyond the supply waits for a fresh order's lead time
--   mobilisation_ok  a crane job starts no sooner than the crane can arrive
--   within_horizon   the job finishes inside the 12-week forecast
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create table if not exists ENGINE.ENG_WINDOW_CANDIDATE (
    window_id               varchar(40)  not null,
    component_id            varchar(30)  not null,
    turbine_id              varchar(20)  not null,
    site_code               varchar(10)  not null,
    component_class_code    varchar(10)  not null,
    crew_id                 varchar(20)  not null,
    part_number             varchar(40)  not null,
    start_day               date         not null,
    end_day                 date         not null,
    job_days                integer      not null,
    requires_crane          boolean      not null,
    crew_certified          boolean      not null,
    crew_available          boolean      not null,
    weather_ok              boolean      not null,
    part_available          boolean      not null,
    mobilisation_ok         boolean      not null,
    within_horizon          boolean      not null,
    is_feasible             boolean      not null,
    part_available_date     date         not null,
    part_source             varchar(200) not null,
    max_forecast_gust_ms    float,
    gust_limit_ms           float        not null,
    crew_conflict           varchar(300),
    risk_rank               integer      not null,
    expected_loss_inr       number(38,0) not null,
    plan_start              date         not null,
    built_at                timestamp_ntz not null,
    is_synthetic            boolean      not null default true,
    constraint pk_eng_window_candidate primary key (window_id)
) comment = 'Candidate maintenance windows with each constraint''s result (CMP-9, FR-33). IS_FEASIBLE is the AND of the six constraint columns; infeasible rows are kept so the binding constraint can be reported.';

create or replace procedure ENGINE.SP_BUILD_WINDOW_CANDIDATES()
returns varchar
language sql
execute as caller
as
$$
declare
    plan_start date;
    n integer;
    n_ok integer;
begin
    select min(issued_on) into :plan_start from RAW.FCT_WIND_FORECAST;

    delete from ENGINE.ENG_WINDOW_CANDIDATE;
    insert into ENGINE.ENG_WINDOW_CANDIDATE
    with jobs as (
        select r.component_id, r.turbine_id, r.site_code, r.component_class_code, r.expected_loss_inr,
               rp.part_number, rp.job_days, rp.requires_crane, rp.required_certification,
               rp.crane_mobilisation_days, rp.max_gust_ms, p.lead_time_days,
               row_number() over (order by r.expected_loss_inr desc, r.component_id)              as risk_rank,
               row_number() over (partition by rp.part_number
                                  order by r.expected_loss_inr desc, r.component_id)              as part_rank
        from ENGINE.ENG_ALERT_RANKED r
        join RAW.DIM_REPAIR_PLAN rp on rp.component_class_code = r.component_class_code
        join RAW.DIM_PART p         on p.part_number = rp.part_number
        where r.risk_band in ('HIGH', 'MEDIUM')
    ),
    -- every unit of supply, in the order it becomes available
    units as (
        select s.part_number, :plan_start as available_date, 'in stock (' || s.warehouse_location || ')' as source
        from RAW.DIM_STOCK s
        join table(generator(rowcount => 100)) g
        where greatest(s.quantity_on_hand - s.quantity_reserved, 0) > 0
        qualify row_number() over (partition by s.stock_id order by seq4()) <= greatest(s.quantity_on_hand - s.quantity_reserved, 0)
        union all
        select i.part_number, i.expected_date, 'open order ' || i.po_id || ', due ' || to_varchar(i.expected_date)
        from RAW.FCT_PART_INBOUND i
        join table(generator(rowcount => 100)) g
        qualify row_number() over (partition by i.po_id order by seq4()) <= i.quantity
    ),
    ranked_units as (
        select part_number, available_date, source,
               row_number() over (partition by part_number order by available_date, source) as unit_rank
        from units
    ),
    supplied as (
        select j.*,
               coalesce(u.available_date, dateadd(day, j.lead_time_days, :plan_start))          as part_available_date,
               coalesce(u.source, 'no unit left: new order, ' || j.lead_time_days || '-day lead time') as part_source
        from jobs j
        left join ranked_units u on u.part_number = j.part_number and u.unit_rank = j.part_rank
    ),
    slots as (
        select s.*, cv.crew_id, c.certifications,
               dateadd(day, g.i, :plan_start)                         as start_day,
               dateadd(day, g.i + s.job_days - 1, :plan_start)        as end_day
        from supplied s
        join RAW.DIM_CREW_COVERAGE cv on cv.site_code = s.site_code
        join RAW.DIM_CREW c           on c.crew_id = cv.crew_id
        cross join (select row_number() over (order by seq4()) - 1 as i from table(generator(rowcount => 84))) g
    ),
    wx as (
        select sl.component_id, sl.crew_id, sl.start_day,
               max(f.forecast_max_gust_ms) as max_gust, count(f.day) as forecast_days
        from slots sl
        left join RAW.FCT_WIND_FORECAST f
               on f.site_code = sl.site_code and f.day between sl.start_day and sl.end_day
        group by sl.component_id, sl.crew_id, sl.start_day
    ),
    busy as (
        select sl.component_id, sl.crew_id, sl.start_day,
               listagg(b.booking_id || ' ' || b.note, '; ') as conflict
        from slots sl
        join RAW.FCT_CRANE_BOOKING b
          on b.crew_id = sl.crew_id and b.start_day <= sl.end_day and b.end_day >= sl.start_day
        group by sl.component_id, sl.crew_id, sl.start_day
    ),
    judged as (
        select sl.*, w.max_gust, bz.conflict,
               array_contains(sl.required_certification::variant, sl.certifications)       as crew_certified,
               bz.conflict is null                                                         as crew_available,
               w.forecast_days = sl.job_days and w.max_gust <= sl.max_gust_ms              as weather_ok,
               sl.start_day >= sl.part_available_date                                      as part_available,
               sl.start_day >= dateadd(day, sl.crane_mobilisation_days, :plan_start)       as mobilisation_ok,
               sl.end_day <= dateadd(day, 83, :plan_start)                                 as within_horizon
        from slots sl
        join wx w on w.component_id = sl.component_id and w.crew_id = sl.crew_id and w.start_day = sl.start_day
        left join busy bz on bz.component_id = sl.component_id and bz.crew_id = sl.crew_id and bz.start_day = sl.start_day
    )
    select 'W-' || substr(sha2(component_id || '|' || crew_id || '|' || to_varchar(start_day)), 1, 16),
           component_id, turbine_id, site_code, component_class_code, crew_id, part_number,
           start_day, end_day, job_days, requires_crane,
           crew_certified, crew_available, weather_ok, part_available, mobilisation_ok, within_horizon,
           crew_certified and crew_available and weather_ok and part_available and mobilisation_ok and within_horizon,
           part_available_date, part_source, max_gust, max_gust_ms, conflict,
           risk_rank, expected_loss_inr, :plan_start, current_timestamp()::timestamp_ntz, true
    from judged;
    n := sqlrowcount;
    select count_if(is_feasible) into :n_ok from ENGINE.ENG_WINDOW_CANDIDATE;
    return n || ' candidate windows from ' || plan_start || ', ' || n_ok || ' feasible';
end;
$$;
