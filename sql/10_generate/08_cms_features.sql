-- =============================================================================
-- 10_generate / 08 — CMS features                              STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-3 (CMS features trend upward before a seeded failure)
-- Proves     : T-8 (gating), and supplies the matched bands US-9/T-2/T-3 need
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §2 stage 4, §4
-- Parameter  : <% database %>
--
-- FEATURES ONLY, NEVER WAVEFORMS (W1). Eight monitored-point/feature pairs per
-- turbine at hourly grain: 100 turbines x 8 x ~4,400 hours is ~3.5M rows, which
-- is what data-sources §3 budgets.
--
-- This is where T-8 lives, so the damage term here is deliberately stronger
-- than in the SCADA temperatures: vibration band energy is the channel a real
-- CMS uses to see bearing wear, and a gearbox HSS bearing on its way out does
-- roughly triple its band energy. The cubic exponent keeps the feature near
-- baseline until damage is well advanced and then climbs steeply, which is the
-- textbook four-stage bearing progression — and it is what gives T-8's lead-in
-- window a detectable margin over the component's own earlier history.
--
-- Every row carries RPM_BAND and LOAD_BAND, because band energy cannot be
-- compared across operating points. A feature that rose only because the
-- turbine was working harder is the single most common false positive in real
-- condition monitoring, and T-3 asserts we do not fall for it.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure GEN.SP_GENERATE_CMS_FEATURES(
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
    rows_written integer;
begin
    delete from RAW.FCT_CMS_FEATURE
    where ts between :window_start and :window_end;

    insert into RAW.FCT_CMS_FEATURE (
        component_id, monitored_point, feature_name, ts, feature_value,
        rpm_band, load_band, operating_state
    )
    with hours as (
        select dateadd(hour, row_number() over (order by seq4()) - 1, :window_start) as ts
        from table(generator(rowcount => 4500))
        qualify ts < :window_end
    ),
    -- the operating point at this hour, from the same wind function the SCADA
    -- signals use: the two cannot disagree about what the turbine was doing
    op as (
        select
            t.turbine_id,
            h.ts,
            p.rated_power_mw * 1000 as rated_kw,
            case when t.platform_id = 'VW-2.1' then 17.0 else 13.5 end as rated_rotor_rpm,
            p.cut_in_speed_ms,
            p.rated_speed_ms,
            p.cut_out_speed_ms,
            GEN.FN_WIND_SPEED(t.turbine_id, h.ts, s.mean_wind_speed, :seed) as wind_ms
        from RAW.DIM_TURBINE t
        join RAW.DIM_SITE s     on s.site_code   = t.site_code
        join RAW.DIM_PLATFORM p on p.platform_id = t.platform_id
        cross join hours h
    ),
    banded as (
        select
            o.turbine_id,
            o.ts,
            o.rated_kw,
            GEN.FN_EXPECTED_POWER(o.wind_ms, o.rated_kw, o.cut_in_speed_ms, o.rated_speed_ms, o.cut_out_speed_ms) as power_kw,
            case
                when o.wind_ms < o.cut_in_speed_ms or o.wind_ms >= o.cut_out_speed_ms then 0.0
                when o.wind_ms >= o.rated_speed_ms then o.rated_rotor_rpm
                else o.rated_rotor_rpm * (o.wind_ms - o.cut_in_speed_ms) / (o.rated_speed_ms - o.cut_in_speed_ms)
            end * 105.0 as gen_rpm
        from op o
    ),
    -- the eight monitored point / feature pairs, with their baselines and how
    -- strongly each responds to load and to damage.
    --
    -- Points exist only for GBX, GEN and MSB, because those are the three
    -- classes DIM_COMPONENT_CLASS marks IS_CMS_MONITORED. An earlier cut had a
    -- TWR-TOP point, which contradicted the dimension: a tower is
    -- inspection-driven, not condition-monitored. Classes without CMS carry
    -- their degradation on a SCADA signal instead (see 07_signals.sql).
    spec as (
        select * from values
            ('GBX', 'GBX-HSS', 'BAND_ENERGY', 2.60, 0.55, 2.40),
            ('GBX', 'GBX-HSS', 'KURTOSIS',    3.10, 0.10, 1.20),
            ('GBX', 'GBX-IMS', 'BAND_ENERGY', 1.90, 0.50, 1.60),
            ('GEN', 'GEN-DE',  'BAND_ENERGY', 1.70, 0.45, 2.00),
            ('GEN', 'GEN-DE',  'KURTOSIS',    3.00, 0.08, 1.10),
            ('GEN', 'GEN-NDE', 'BAND_ENERGY', 1.50, 0.45, 1.40),
            ('MSB', 'MSB-RAD', 'BAND_ENERGY', 1.20, 0.60, 1.80),
            ('MSB', 'MSB-RAD', 'KURTOSIS',    3.00, 0.08, 1.00)
        as s(cc, point, feature, baseline, load_gain, damage_gain)
    ),
    -- damage for the owning component, per day
    dmg as (
        select
            component_id,
            ts::date as day,
            damage_level / nullif(failure_threshold, 0) as damage_ratio
        from GEN.GEN_DAMAGE_STATE
    )
    select
        c.component_id,
        sp.point,
        sp.feature,
        b.ts,
        round(
            sp.baseline
            -- g(operating point): band energy rises with load
            * (1 + sp.load_gain * (b.power_kw / nullif(b.rated_kw, 0)))
            -- f(damage): flat while damage is low, climbing steeply as the
            -- instance approaches its threshold. The cubic exponent is what
            -- separates the lead-in window from the baseline window by a margin
            -- T-8 can assert; a linear term left half the seeded failures
            -- indistinguishable from their own history.
            * (1 + sp.damage_gain * pow(coalesce(d.damage_ratio, 0), 3.0))
            -- measurement noise
            * (1 + 0.08 * (GEN.FN_RAND(c.component_id || sp.point || sp.feature || to_varchar(b.ts, 'YYYYMMDDHH24'), :seed || 'cms') - 0.5)),
            6
        ),
        GEN.FN_RPM_BAND(b.gen_rpm),
        GEN.FN_LOAD_BAND(b.power_kw, b.rated_kw),
        case
            when b.power_kw > 0 then 'RUNNING'
            else 'IDLE'
        end
    from banded b
    join RAW.DIM_COMPONENT c on c.turbine_id = b.turbine_id
    join spec sp            on sp.cc = c.component_class_code
    left join dmg d         on d.component_id = c.component_id and d.day = b.ts::date;

    rows_written := sqlrowcount;
    return 'FCT_CMS_FEATURE: ' || rows_written || ' rows';
end;
$$;
