-- =============================================================================
-- 10_generate / 14 — planning context for the window engine        STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the inputs CMP-9 needs (FR-33): forecast wind, crew certification
--              and coverage, crane-team commitments, repair plan, open orders
-- Proves     : nothing on its own; T-31 re-checks every candidate against these
-- Authority  : docs/03-architecture/03-component.md CMP-9 (the constraint list),
--              ADR-0018 (rolling 12 weeks)
-- Parameter  : <% database %>
--
-- ===================== WHY THIS IS GENERATED, AND WHAT IS INVENTED ============
--
-- The data had no forecast, no crane calendar and empty crew certifications,
-- so a window engine would have had nothing to constrain against. Everything
-- here is SYNTHETIC and labelled so; the choices below are ours, not Vayuveda's:
--
--   forecast      12 weeks from the day after the data ends, per site. Seasonal:
--                 the south-west monsoon (Jun-Sep) is windy, October calms,
--                 November-December calmer still. Crane lifts need gusts
--                 <= 10 m/s, up-tower work <= 15 m/s (FN below).
--   certification site crews UPTOWER + ELECTRICAL, three also DRIVETRAIN; the two
--                 crane teams CRANE + DRIVETRAIN + UPTOWER
--   coverage      each site crew covers its base site; the South crane team
--                 covers KA-CTD, KA-GDG and TN-TVL, the West team GJ-KCH, MH-STR
--                 and RJ-JSM
--   commitments   each crane team is already committed for part of the horizon
--   open order    one PT-MSB-BEAR on order, arriving in five weeks
--   repair plan   per component class: the part a draft would use (the costliest,
--                 as SP_DRAFT_WORK_ORDER picks it), job days, crane mobilisation
--
-- Deterministic from (window_end, seed); delete-and-reload, so re-running is safe.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create table if not exists RAW.FCT_WIND_FORECAST (
    site_code              varchar(10) not null,
    day                    date        not null,
    forecast_mean_wind_ms  float       not null,
    forecast_max_gust_ms   float       not null,
    issued_on              date        not null,
    is_synthetic           boolean     not null default true,
    constraint pk_fct_wind_forecast primary key (site_code, day)
) comment = 'Synthetic daily wind forecast, 12 weeks ahead, per site. Crane lifts need gust <= 10 m/s; up-tower <= 15 m/s.';

create table if not exists RAW.DIM_CREW_COVERAGE (
    crew_id      varchar(20) not null,
    site_code    varchar(10) not null,
    is_synthetic boolean     not null default true,
    constraint pk_dim_crew_coverage primary key (crew_id, site_code)
) comment = 'Which sites each crew can work at.';

create table if not exists RAW.FCT_CRANE_BOOKING (
    booking_id   varchar(20) not null,
    crew_id      varchar(20) not null,
    start_day    date        not null,
    end_day      date        not null,
    note         varchar(300),
    is_synthetic boolean     not null default true,
    constraint pk_fct_crane_booking primary key (booking_id)
) comment = 'Existing commitments of the crane teams. A window overlapping one is infeasible for that team.';

create table if not exists RAW.FCT_PART_INBOUND (
    po_id          varchar(20) not null,
    part_number    varchar(40) not null,
    quantity       integer     not null,
    expected_date  date        not null,
    is_synthetic   boolean     not null default true,
    constraint pk_fct_part_inbound primary key (po_id)
) comment = 'Open purchase orders: parts already on the way, with their expected arrival.';

create table if not exists RAW.DIM_REPAIR_PLAN (
    component_class_code    varchar(10) not null,
    part_number             varchar(40) not null,
    job_days                integer     not null,
    requires_crane          boolean     not null,
    required_certification  varchar(20) not null,
    crane_mobilisation_days integer     not null,
    max_gust_ms             float       not null,
    is_synthetic            boolean     not null default true,
    constraint pk_dim_repair_plan primary key (component_class_code)
) comment = 'How each component class is repaired: part, job length, crane need and mobilisation lead, certification, wind limit.';

create or replace procedure GEN.SP_GENERATE_PLANNING_CONTEXT(
    window_start timestamp_ntz,
    window_end   timestamp_ntz,
    seed         varchar
)
returns varchar
language sql
execute as caller
as
$$
declare
    plan_start date;
    n_fc integer;
begin
    plan_start := dateadd(day, 1, window_end::date);

    -- CERTIFICATIONS is a VARIANT column: an array of codes.
    update RAW.DIM_CREW
       set certifications = case
               when crew_id like 'CRW-CR%'                          then array_construct('CRANE', 'DRIVETRAIN', 'UPTOWER')
               when crew_id in ('CRW-N01', 'CRW-S01', 'CRW-W01')    then array_construct('UPTOWER', 'ELECTRICAL', 'DRIVETRAIN')
               else                                                    array_construct('UPTOWER', 'ELECTRICAL')
           end;

    delete from RAW.DIM_CREW_COVERAGE;
    insert into RAW.DIM_CREW_COVERAGE (crew_id, site_code)
    select crew_id, base_site_code from RAW.DIM_CREW where base_site_code is not null
    union all select 'CRW-CR01', column1 from values ('KA-CTD'), ('KA-GDG'), ('TN-TVL')
    union all select 'CRW-CR02', column1 from values ('GJ-KCH'), ('MH-STR'), ('RJ-JSM');

    -- The part is the one a draft uses (costliest per class), so the engine and
    -- SP_DRAFT_WORK_ORDER can never disagree about what the job needs.
    delete from RAW.DIM_REPAIR_PLAN;
    insert into RAW.DIM_REPAIR_PLAN (component_class_code, part_number, job_days, requires_crane,
                                     required_certification, crane_mobilisation_days, max_gust_ms)
    select p.component_class_code, p.part_number,
           decode(p.component_class_code, 'GBX', 5, 'MSB', 4, 'GEN', 3, 'BLD', 3, 'PIT', 2, 'TRF', 2, 'YAW', 2, 1),
           coalesce(p.requires_crane, false),
           case when coalesce(p.requires_crane, false) then 'CRANE'
                when c.is_drivetrain                    then 'DRIVETRAIN'
                when p.component_class_code = 'CNV'     then 'ELECTRICAL'
                else 'UPTOWER' end,
           iff(coalesce(p.requires_crane, false), iff(p.component_class_code in ('PIT', 'TRF'), 10, 14), 0),
           iff(coalesce(p.requires_crane, false), 10.0, 15.0)
    from RAW.DIM_PART p
    join RAW.DIM_COMPONENT_CLASS c on c.component_class_code = p.component_class_code
    qualify row_number() over (partition by p.component_class_code order by p.unit_cost_inr desc, p.part_number) = 1;

    delete from RAW.FCT_WIND_FORECAST;
    insert into RAW.FCT_WIND_FORECAST (site_code, day, forecast_mean_wind_ms, forecast_max_gust_ms, issued_on)
    with d as (
        select s.site_code, s.mean_wind_speed, dateadd(day, g.i, :plan_start) as day
        from RAW.DIM_SITE s
        cross join (select row_number() over (order by seq4()) - 1 as i from table(generator(rowcount => 84))) g
    ),
    m as (
        select site_code, day,
               mean_wind_speed
                 * decode(month(day), 6, 1.45, 7, 1.45, 8, 1.40, 9, 1.25, 10, 0.95, 11, 0.80, 12, 0.80, 1.0)
                 * (0.75 + 0.5 * GEN.FN_RAND(site_code || to_varchar(day), :seed || 'fcst')) as mean_ms
        from d
    )
    select site_code, day, round(mean_ms, 2),
           round(mean_ms * 1.5 * (0.9 + 0.2 * GEN.FN_RAND(site_code || to_varchar(day), :seed || 'gust')), 2),
           :plan_start
    from m;
    n_fc := sqlrowcount;

    delete from RAW.FCT_CRANE_BOOKING;
    insert into RAW.FCT_CRANE_BOOKING (booking_id, crew_id, start_day, end_day, note)
    select column1, column2, dateadd(day, column3, :plan_start), dateadd(day, column4, :plan_start), column5
    from values
        ('CB-01', 'CRW-CR01', 14, 27, 'Committed: blade campaign at KA-GDG (existing plan)'),
        ('CB-02', 'CRW-CR02', 20, 30, 'Committed: transformer lift at RJ-JSM (existing plan)');

    delete from RAW.FCT_PART_INBOUND;
    insert into RAW.FCT_PART_INBOUND (po_id, part_number, quantity, expected_date)
    select 'PO-MSB-01', 'PT-MSB-BEAR', 1, dateadd(day, 35, :plan_start);

    return 'planning context from ' || plan_start || ': ' || n_fc || ' forecast site-days, 8 crews certified, 2 crane bookings, 1 open order';
end;
$$;
