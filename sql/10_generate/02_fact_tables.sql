-- =============================================================================
-- 10_generate / 02 — fact tables                             STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-8 (landing tables for every source)
-- Authority  : docs/04-data/data-model.md §2 (grain), 04-code.md §3 (naming)
-- Parameter  : <% database %>
--
-- Grain is stated per table per data-model.md. Clustering follows §7.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- FCT_SIGNAL_10MIN — one row per turbine × signal × 10-minute interval
-- ---------------------------------------------------------------------------
create table if not exists RAW.FCT_SIGNAL_10MIN (
    turbine_id        varchar(20)     not null,
    signal_id         varchar(60)     not null,
    ts                timestamp_ntz   not null,
    value_avg         number(12,4),
    value_min         number(12,4),
    value_max         number(12,4),
    value_std         number(12,4),
    operating_state   varchar(20),
    is_synthetic      boolean         not null default true
)
cluster by (turbine_id, ts);

-- ---------------------------------------------------------------------------
-- FCT_CMS_FEATURE — one row per component × monitored point × feature × hour
-- ---------------------------------------------------------------------------
create table if not exists RAW.FCT_CMS_FEATURE (
    component_id      varchar(30)     not null,
    monitored_point   varchar(60)     not null,
    feature_name      varchar(60)     not null,
    ts                timestamp_ntz   not null,
    feature_value     number(14,6),
    rpm_band          varchar(20),
    load_band         varchar(20),
    operating_state   varchar(20),
    is_synthetic      boolean         not null default true
)
cluster by (component_id, ts);

-- ---------------------------------------------------------------------------
-- FCT_TURBINE_STATE — one row per turbine × state interval (start, end)
-- ---------------------------------------------------------------------------
create table if not exists RAW.FCT_TURBINE_STATE (
    turbine_id          varchar(20)     not null,
    state_start         timestamp_ntz   not null,
    state_end           timestamp_ntz,
    operating_state     varchar(20)     not null,
    state_reason        varchar(100),
    exclusion_class_code varchar(20),
    is_synthetic        boolean         not null default true
);

-- ---------------------------------------------------------------------------
-- FCT_ALARM_NORMALISED — one row per alarm occurrence, any of the four sources
-- ---------------------------------------------------------------------------
create table if not exists RAW.FCT_ALARM_NORMALISED (
    alarm_id            varchar(40)     not null,
    turbine_id          varchar(20)     not null,
    component_id        varchar(30),
    alarm_code          varchar(20)     not null,
    alarm_source        varchar(20)     not null,
    alarm_start         timestamp_ntz   not null,
    alarm_end           timestamp_ntz,
    is_auto_reset       boolean         not null default false,
    acknowledged_at     timestamp_ntz,
    site_code           varchar(10)     not null,
    is_synthetic        boolean         not null default true,
    constraint pk_alarm primary key (alarm_id)
);

-- ---------------------------------------------------------------------------
-- FCT_WORK_ORDER — one row per work order
-- ---------------------------------------------------------------------------
create table if not exists RAW.FCT_WORK_ORDER (
    work_order_id       varchar(30)     not null,
    turbine_id          varchar(20)     not null,
    component_id        varchar(30)     not null,
    work_order_type     varchar(30)     not null,
    failure_code        varchar(20),
    cause_description   varchar(500),
    remedy_description  varchar(500),
    technician_notes    varchar(1000),
    status              varchar(30)     not null default 'OPEN',
    priority            varchar(20),
    created_date        timestamp_ntz   not null,
    scheduled_date      timestamp_ntz,
    completed_date      timestamp_ntz,
    downtime_hours      number(8,2),
    labour_hours        number(8,2),
    crew_id             varchar(20),
    requires_crane      boolean         not null default false,
    is_synthetic        boolean         not null default true,
    constraint pk_work_order primary key (work_order_id)
);

-- ---------------------------------------------------------------------------
-- FCT_PART_MOVEMENT — one row per part movement
-- ---------------------------------------------------------------------------
create table if not exists RAW.FCT_PART_MOVEMENT (
    movement_id         varchar(30)     not null,
    work_order_id       varchar(30),
    part_number         varchar(30)     not null,
    stock_id            varchar(30),
    movement_type       varchar(20)     not null,
    quantity            integer         not null,
    movement_date       timestamp_ntz   not null,
    is_synthetic        boolean         not null default true,
    constraint pk_part_movement primary key (movement_id)
);

-- ---------------------------------------------------------------------------
-- GEN.GEN_DAMAGE_STATE — internal generator state, not a landing table
-- Tracks accumulated damage per component instance for the generator.
-- Lives in GEN because it is generator machinery, not application data.
-- ---------------------------------------------------------------------------
create table if not exists GEN.GEN_DAMAGE_STATE (
    component_id          varchar(30)   not null,
    serial_number         varchar(30)   not null,
    ts                    timestamp_ntz not null,
    damage_level          number(10,6)  not null default 0.0,
    failure_threshold     number(10,6)  not null,
    has_failed            boolean       not null default false,
    failure_ts            timestamp_ntz,
    is_synthetic          boolean       not null default true
);
