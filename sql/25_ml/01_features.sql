-- =============================================================================
-- 25_ml / 01 — features and label                              STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-18 (features per component class at matched conditions)
-- Proves     : supports T-10, T-14, T-15; feeds SCORE_ and DRIVER_
-- Authority  : docs/05-ai-ml/ml-models.md §3 (features), §4 (label), ADR-0014
-- Parameter  : <% database %>
--
-- ===================== THE LEAKAGE RULE, STATED ONCE =========================
--
-- FEATURES COME ONLY FROM OBSERVABLE DATA. GEN.GEN_DAMAGE_STATE IS NOT A FEATURE
-- AND MUST NEVER BECOME ONE.
--
-- Damage is the generator's hidden ground truth. It is, by construction, almost
-- perfectly predictive of failure — GEN_DAMAGE_STATE crossing its threshold IS
-- the failure. A model given damage as an input would score beautifully and mean
-- nothing, and it would be the reference solution's defect wearing better
-- clothes: health as a function of something the real world cannot measure.
--
-- So features are drawn from RAW.FCT_CMS_FEATURE, RAW.FCT_SIGNAL_10MIN and the
-- dimensions — things a real fleet actually records. GEN_FAILURE_EVENT is used
-- for the LABEL only, which is legitimate: that is what a maintenance history
-- gives you.
--
-- ===================== SCOPE, AND ONE HONEST ADJUSTMENT ======================
--
-- ADR-0014 scopes the model to four classes with "real CMS coverage": GBX, MSB,
-- GEN, PIT. But DIM_COMPONENT_CLASS marks only THREE as IS_CMS_MONITORED — GBX,
-- GEN, MSB — and the generator followed the dimension, so PIT has no monitored
-- point at all.
--
-- Rather than silently drop PIT (which would quietly narrow a documented scope)
-- or feed it nulls (which would let it look predictable when it is not), each
-- class gets a named PRIMARY DEGRADATION CHANNEL: band energy for the three CMS
-- classes, and pitch motor current for PIT. Motor current rising with wear is
-- real physics and it is the only observable PIT has. The channel used is
-- recorded per row so nothing downstream has to guess.
--
-- ===================== BANDING IS NOT OPTIONAL ===============================
--
-- Every signal feature is computed WITHIN MATCHED LOAD BANDS (HIGH, FULL). By
-- design g(operating point) is large relative to f(damage) (ADR-0006), so an
-- unbanded model learns the wind rather than the wear. ml-models.md §3 calls this
-- the subtlest data work in the build.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- FEAT_COMPONENT_DAILY — one row per in-scope component per day.
-- ---------------------------------------------------------------------------
create table if not exists ML.FEAT_COMPONENT_DAILY (
    component_id            varchar(30)   not null,
    turbine_id              varchar(20)   not null,
    component_class_code    varchar(3)    not null,
    feature_date            date          not null,
    -- the class's primary degradation channel, and which one it was
    primary_channel         varchar(60),
    primary_mean            number(16,6),
    primary_p95             number(16,6),
    -- deviation from this component's OWN earlier behaviour, not the fleet's
    primary_vs_own_baseline number(16,6),
    -- degradation is a change, not a level (ml-models.md §3)
    trend_7d                number(16,6),
    trend_14d               number(16,6),
    trend_30d               number(16,6),
    trend_accel             number(16,6),
    -- thermal confirmation, and the cross-signal divergence
    thermal_rise            number(16,6),
    vib_temp_divergence     number(16,6),
    -- operating exposure: the damage driver
    hours_high_load_7d      number(10,2),
    starts_7d               integer,
    -- context
    age_days                integer,
    platform_id             varchar(10),
    site_stressor_factor    number(10,4),
    days_since_intervention integer,
    -- label and its provenance
    failed_within_horizon   boolean       not null default false,
    horizon_days            integer       not null default 30,
    label_excluded          boolean       not null default false,
    is_synthetic            boolean       not null default true,
    constraint pk_feat_component_daily primary key (component_id, feature_date)
);

-- ---------------------------------------------------------------------------
-- SP_BUILD_FEATURES — rebuild the feature table for a window.
-- ---------------------------------------------------------------------------
create or replace procedure ML.SP_BUILD_FEATURES(
    horizon_days integer
)
returns varchar
language sql
execute as caller
as
$$
declare
    rows_written integer;
    n_positive   integer;
begin
    -- ---- which channel each class is watched on -------------------------
    create or replace temporary table ML.ML_TMP_CHANNEL as
    select * from values
        ('GBX', 'CMS',   'GBX-HSS', 'TEMP_GBX_HSS'),
        ('GEN', 'CMS',   'GEN-DE',  'TEMP_GEN_BEAR'),
        ('MSB', 'CMS',   'MSB-RAD', 'TEMP_MSB'),
        ('PIT', 'SCADA', 'PITCH_MOTOR_I', null)
    as s(component_class_code, channel_kind, channel_name, thermal_signal);

    -- ---- daily primary channel, within matched load bands ---------------
    create or replace temporary table ML.ML_TMP_PRIMARY as
    -- CMS classes: band energy at the primary monitored point
    select
        c.component_id,
        f.ts::date                       as feature_date,
        avg(f.feature_value)             as primary_mean,
        approx_percentile(f.feature_value, 0.95) as primary_p95
    from RAW.FCT_CMS_FEATURE f
    join RAW.DIM_COMPONENT c on c.component_id = f.component_id
    join ML.ML_TMP_CHANNEL ch
        on  ch.component_class_code = c.component_class_code
        and ch.channel_kind         = 'CMS'
        and ch.channel_name         = f.monitored_point
    where f.feature_name = 'BAND_ENERGY'
      and f.load_band in ('HIGH', 'FULL')       -- matched conditions
    group by 1, 2

    union all

    -- PIT: motor current, the only observable it has
    select
        ds.component_id,
        s.ts::date,
        avg(s.value_avg),
        approx_percentile(s.value_avg, 0.95)
    from RAW.FCT_SIGNAL_10MIN s
    join RAW.DIM_SIGNAL ds   on ds.signal_id    = s.signal_id
    join RAW.DIM_COMPONENT c on c.component_id  = ds.component_id
    join ML.ML_TMP_CHANNEL ch
        on  ch.component_class_code = c.component_class_code
        and ch.channel_kind         = 'SCADA'
        and ch.channel_name         = ds.signal_name
    where s.operating_state = 'RUNNING'
    group by 1, 2;

    -- ---- daily thermal channel, same band control -----------------------
    create or replace temporary table ML.ML_TMP_THERMAL as
    select
        ds.component_id,
        s.ts::date            as feature_date,
        avg(s.value_avg)      as temp_mean,
        -- rise above what the fleet does on the same day at the same load:
        -- an absolute temperature says more about the weather than the bearing
        avg(s.value_avg) - avg(avg(s.value_avg)) over (partition by s.ts::date, ds.signal_name)
                              as temp_rise_vs_fleet
    from RAW.FCT_SIGNAL_10MIN s
    join RAW.DIM_SIGNAL ds on ds.signal_id = s.signal_id
    join RAW.DIM_COMPONENT c on c.component_id = ds.component_id
    join ML.ML_TMP_CHANNEL ch
        on  ch.component_class_code = c.component_class_code
        and ch.thermal_signal       = ds.signal_name
    where s.operating_state = 'RUNNING'
    group by ds.component_id, s.ts::date, ds.signal_name;

    -- ---- operating exposure per turbine-day -----------------------------
    create or replace temporary table ML.ML_TMP_EXPOSURE as
    select
        turbine_id,
        day                        as feature_date,
        round(capacity_factor * 24, 2) as hours_high_load,
        hours_below_cutin
    from GEN.GEN_TURBINE_DAY;

    -- ---- the feature table ----------------------------------------------
    delete from ML.FEAT_COMPONENT_DAILY;

    insert into ML.FEAT_COMPONENT_DAILY (
        component_id, turbine_id, component_class_code, feature_date,
        primary_channel, primary_mean, primary_p95, primary_vs_own_baseline,
        trend_7d, trend_14d, trend_30d, trend_accel,
        thermal_rise, vib_temp_divergence,
        hours_high_load_7d, starts_7d,
        age_days, platform_id, site_stressor_factor, days_since_intervention,
        failed_within_horizon, horizon_days, label_excluded
    )
    with base as (
        select
            c.component_id,
            c.turbine_id,
            c.component_class_code,
            p.feature_date,
            ch.channel_name as primary_channel,
            p.primary_mean,
            p.primary_p95,
            t.temp_rise_vs_fleet,
            e.hours_high_load,
            e.hours_below_cutin,
            datediff(day, c.install_date, p.feature_date) as age_days,
            tb.platform_id,
            ss.stressor_factor
        from ML.ML_TMP_PRIMARY p
        join RAW.DIM_COMPONENT c  on c.component_id = p.component_id
        join RAW.DIM_TURBINE tb   on tb.turbine_id  = c.turbine_id
        join ML.ML_TMP_CHANNEL ch on ch.component_class_code = c.component_class_code
        join GEN.GEN_SITE_STRESSOR ss on ss.site_code = tb.site_code
        left join ML.ML_TMP_THERMAL t
            on t.component_id = p.component_id and t.feature_date = p.feature_date
        left join ML.ML_TMP_EXPOSURE e
            on e.turbine_id = c.turbine_id and e.feature_date = p.feature_date
    ),
    windowed as (
        select
            b.*,
            -- the component's own earlier behaviour is the only fair reference:
            -- a fleet-wide comparison penalises a site that is simply harsher
            avg(b.primary_mean) over (
                partition by b.component_id order by b.feature_date
                rows between 44 preceding and 30 preceding
            ) as own_baseline,
            -- slopes as (now - then) / days, cheap and interpretable
            (b.primary_mean - lag(b.primary_mean, 7)  over (partition by b.component_id order by b.feature_date)) / 7.0  as trend_7d,
            (b.primary_mean - lag(b.primary_mean, 14) over (partition by b.component_id order by b.feature_date)) / 14.0 as trend_14d,
            (b.primary_mean - lag(b.primary_mean, 30) over (partition by b.component_id order by b.feature_date)) / 30.0 as trend_30d,
            sum(b.hours_high_load) over (
                partition by b.turbine_id order by b.feature_date
                rows between 6 preceding and current row
            ) as hours_high_load_7d,
            -- a proxy for start-stop cycling: days the turbine sat below cut-in
            sum(case when b.hours_below_cutin > 6 then 1 else 0 end) over (
                partition by b.turbine_id order by b.feature_date
                rows between 6 preceding and current row
            ) as starts_7d
        from base b
    ),
    labelled as (
        select
            w.*,
            fe.failure_ts,
            fe.repair_ts,
            -- POSITIVE: inside the horizon before a failure on this component
            case
                when fe.failure_ts is not null
                 and w.feature_date <  fe.failure_ts::date
                 and w.feature_date >= dateadd(day, -:horizon_days, fe.failure_ts::date)
                then true else false
            end as is_positive,
            -- EXCLUDED: after failure, before repair completes. The component is
            -- not in service, so a prediction about it is meaningless.
            case
                when fe.failure_ts is not null
                 and w.feature_date >= fe.failure_ts::date
                 and w.feature_date <  coalesce(fe.repair_ts::date, '9999-12-31'::date)
                then true else false
            end as is_excluded,
            coalesce(
                datediff(day, max(gg.valid_from) over (partition by w.component_id), w.feature_date),
                w.age_days
            ) as days_since_intervention
        from windowed w
        left join GEN.GEN_FAILURE_EVENT fe on fe.component_id = w.component_id
        left join RAW.DIM_COMPONENT_GENEALOGY gg
            on gg.component_id = w.component_id and gg.valid_from::date <= w.feature_date
    )
    select
        component_id,
        turbine_id,
        component_class_code,
        feature_date,
        primary_channel,
        round(primary_mean, 6),
        round(primary_p95, 6),
        round(primary_mean - own_baseline, 6),
        round(trend_7d, 6),
        round(trend_14d, 6),
        round(trend_30d, 6),
        round(trend_7d - trend_30d, 6),           -- acceleration
        round(temp_rise_vs_fleet, 6),
        -- divergence: primary channel moving without the temperature following is
        -- mechanical wear; both moving together is more likely load or cooling
        round((primary_mean - own_baseline) - coalesce(temp_rise_vs_fleet, 0), 6),
        round(hours_high_load_7d, 2),
        starts_7d,
        age_days,
        platform_id,
        stressor_factor,
        days_since_intervention,
        is_positive,
        :horizon_days,
        is_excluded
    from labelled
    -- ADR-0014 scope
    where component_class_code in ('GBX', 'GEN', 'MSB', 'PIT')
      -- a row with no own-baseline has no trend to speak of; those are the first
      -- 44 days of the window and they are context, not training data
      and own_baseline is not null
    qualify row_number() over (partition by component_id, feature_date order by feature_date) = 1;

    rows_written := sqlrowcount;

    select count_if(failed_within_horizon) into :n_positive from ML.FEAT_COMPONENT_DAILY;

    return 'FEAT_COMPONENT_DAILY: ' || rows_written || ' component-days, '
        || n_positive || ' positive (horizon ' || :horizon_days || 'd)';
end;
$$;
