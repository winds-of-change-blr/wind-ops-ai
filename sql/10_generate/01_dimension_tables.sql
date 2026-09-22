-- =============================================================================
-- 10_generate / 01 — dimension tables                        STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-1, US-8 (landing tables)
-- Authority  : docs/04-data/data-model.md, docs/03-architecture/04-code.md §3
-- Parameter  : <% database %>
--
-- CREATE OR ALTER for tables that may hold data on a re-run (T-52 idempotency).
-- All timestamps TIMESTAMP_NTZ in IST (data-model.md §7).
-- Every table carries IS_SYNTHETIC (FR-15, T-13).
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- DIM_COMPONENT_CLASS — the 10 component types
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_COMPONENT_CLASS (
    component_class_code    varchar(3)    not null,
    component_class_name    varchar(100)  not null,
    is_drivetrain           boolean       not null default false,
    is_cms_monitored        boolean       not null default false,
    repair_profile          varchar(200),
    is_synthetic            boolean       not null default true,
    constraint pk_component_class primary key (component_class_code)
);

-- ---------------------------------------------------------------------------
-- DIM_PLATFORM — VW-2.1 and VW-3.0
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_PLATFORM (
    platform_id       varchar(10)   not null,
    platform_name     varchar(100)  not null,
    rated_power_mw    number(4,2)   not null,
    cut_in_speed_ms   number(4,1)   not null default 3.0,
    rated_speed_ms    number(4,1)   not null default 12.0,
    cut_out_speed_ms  number(4,1)   not null default 25.0,
    rotor_diameter_m  number(5,1),
    hub_height_m      number(5,1),
    is_synthetic      boolean       not null default true,
    constraint pk_platform primary key (platform_id)
);

-- ---------------------------------------------------------------------------
-- DIM_SITE — 6 wind parks
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_SITE (
    site_code         varchar(10)   not null,
    site_name         varchar(200)  not null,
    state             varchar(50)   not null,
    region            varchar(20)   not null,
    mean_wind_speed   number(4,1),
    site_stressor     varchar(200),
    turbine_count     integer       not null,
    is_synthetic      boolean       not null default true,
    constraint pk_site primary key (site_code)
);

-- ---------------------------------------------------------------------------
-- DIM_CONTRACT — one per site, with guarantee stepping
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_CONTRACT (
    contract_id             varchar(20)   not null,
    site_code               varchar(10)   not null,
    customer_type           varchar(50)   not null,
    start_date              date          not null,
    duration_years          integer       not null default 10,
    guarantee_yr1_2_pct     number(5,2)   not null default 95.00,
    guarantee_yr3_plus_pct  number(5,2)   not null default 97.00,
    ld_rate_per_turbine_per_pct  number(10,2) not null default 50000.00,
    scheduled_maint_hours_yr     number(6,1)  not null default 200.0,
    is_synthetic            boolean       not null default true,
    constraint pk_contract primary key (contract_id)
);

-- ---------------------------------------------------------------------------
-- DIM_EXCLUSION_CLASS — availability exclusions
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_EXCLUSION_CLASS (
    exclusion_class_code  varchar(20)   not null,
    exclusion_class_name  varchar(100)  not null,
    description           varchar(500),
    is_synthetic          boolean       not null default true,
    constraint pk_exclusion_class primary key (exclusion_class_code)
);

-- ---------------------------------------------------------------------------
-- DIM_TURBINE — 100 turbines
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_TURBINE (
    turbine_id        varchar(20)   not null,
    site_code         varchar(10)   not null,
    platform_id       varchar(10)   not null,
    commissioned_date date          not null,
    latitude          number(9,6),
    longitude         number(9,6),
    uns_path          varchar(200),
    is_synthetic      boolean       not null default true,
    constraint pk_turbine primary key (turbine_id)
);

-- ---------------------------------------------------------------------------
-- DIM_COMPONENT — 1,000 component positions (10 per turbine)
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_COMPONENT (
    component_id          varchar(30)   not null,
    turbine_id            varchar(20)   not null,
    component_class_code  varchar(3)    not null,
    installed_serial      varchar(30),
    install_date          date,
    uns_path              varchar(200),
    is_synthetic          boolean       not null default true,
    constraint pk_component primary key (component_id)
);

-- ---------------------------------------------------------------------------
-- DIM_COMPONENT_GENEALOGY — serial history per position
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_COMPONENT_GENEALOGY (
    component_id      varchar(30)   not null,
    serial_number     varchar(30)   not null,
    valid_from        timestamp_ntz not null,
    valid_to          timestamp_ntz,
    event_type        varchar(30)   not null,
    is_synthetic      boolean       not null default true
);

-- ---------------------------------------------------------------------------
-- DIM_SIGNAL — ~40 signals per turbine
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_SIGNAL (
    signal_id             varchar(60)   not null,
    turbine_id            varchar(20)   not null,
    component_id          varchar(30),
    signal_name           varchar(100)  not null,
    signal_type           varchar(30)   not null,
    unit                  varchar(20),
    normal_range_low      number(10,3),
    normal_range_high     number(10,3),
    is_synthetic          boolean       not null default true,
    constraint pk_signal primary key (signal_id)
);

-- ---------------------------------------------------------------------------
-- DIM_ALARM_CODE — alarm code catalogue with safety-critical flags
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_ALARM_CODE (
    alarm_code            varchar(20)   not null,
    alarm_source          varchar(20)   not null,
    alarm_name            varchar(200)  not null,
    severity              varchar(20)   not null,
    component_class_code  varchar(3),
    is_safety_critical    boolean       not null default false,
    auto_reset_eligible   boolean       not null default false,
    description           varchar(500),
    is_synthetic          boolean       not null default true,
    constraint pk_alarm_code primary key (alarm_code)
);

-- ---------------------------------------------------------------------------
-- DIM_FAILURE_CODE — failure taxonomy
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_FAILURE_CODE (
    failure_code          varchar(20)   not null,
    failure_name          varchar(200)  not null,
    component_class_code  varchar(3)    not null,
    failure_category      varchar(50)   not null,
    is_synthetic          boolean       not null default true,
    constraint pk_failure_code primary key (failure_code)
);

-- ---------------------------------------------------------------------------
-- DIM_CREW — field crews with skills and certifications
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_CREW (
    crew_id               varchar(20)   not null,
    crew_name             varchar(100)  not null,
    base_site_code        varchar(10),
    region                varchar(20)   not null,
    certifications        variant,
    max_turbines_per_day  integer       not null default 2,
    is_synthetic          boolean       not null default true,
    constraint pk_crew primary key (crew_id)
);

-- ---------------------------------------------------------------------------
-- DIM_PART — spare parts catalogue
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_PART (
    part_number           varchar(30)   not null,
    part_name             varchar(200)  not null,
    component_class_code  varchar(3)    not null,
    lead_time_days        integer       not null,
    unit_cost_inr         number(12,2)  not null,
    requires_crane        boolean       not null default false,
    is_synthetic          boolean       not null default true,
    constraint pk_part primary key (part_number)
);

-- ---------------------------------------------------------------------------
-- DIM_STOCK — inventory levels per warehouse/site
-- ---------------------------------------------------------------------------
create table if not exists RAW.DIM_STOCK (
    stock_id              varchar(60)   not null,
    part_number           varchar(30)   not null,
    warehouse_location    varchar(50)   not null,
    quantity_on_hand      integer       not null default 0,
    quantity_reserved     integer       not null default 0,
    last_updated          timestamp_ntz not null,
    is_synthetic          boolean       not null default true,
    constraint pk_stock primary key (stock_id)
);
