-- =============================================================================
-- 10_generate / 03 — seed dimension data from company profile
-- =============================================================================
-- Implements : US-1 (fleet, turbines, components, signals from profile)
-- Authority  : docs/01-business/company-profile.md §4, §5, §2
-- Parameter  : <% database %>
--
-- Idempotent: MERGE or INSERT with NOT EXISTS. Re-runnable without duplication.
-- Every value traces to the company profile or data-sources doc.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- Component classes — profile §5, 10 components per turbine
-- ---------------------------------------------------------------------------
merge into RAW.DIM_COMPONENT_CLASS tgt
using (
    select * from values
        ('BLD', 'Rotor Blades',         false, false, 'Rope-access repair; replacement needs a crane'),
        ('PIT', 'Pitch System',          false, false, 'Up-tower mostly; bearing needs a crane'),
        ('MSB', 'Main Shaft & Bearing',  true,  true,  'Major; crane'),
        ('GBX', 'Gearbox',              true,  true,  'Bearing up-tower if caught early; full swap needs a crane'),
        ('GEN', 'Generator',            true,  true,  'Bearing up-tower; stator or rotor needs a crane'),
        ('CNV', 'Power Converter',       false, false, 'Up-tower module swap'),
        ('TRF', 'Unit Transformer',      false, false, 'Ground level; replacement needs lifting'),
        ('YAW', 'Yaw System',           false, false, 'Up-tower'),
        ('NAC', 'Nacelle Auxiliaries',    false, false, 'Up-tower'),
        ('TWR', 'Tower & Foundation',     false, false, 'Inspection-driven')
    as s(code, name, drivetrain, cms, repair)
) src
on tgt.component_class_code = src.code
when not matched then insert (component_class_code, component_class_name, is_drivetrain, is_cms_monitored, repair_profile)
    values (src.code, src.name, src.drivetrain, src.cms, src.repair);

-- ---------------------------------------------------------------------------
-- Platforms — profile §1
-- ---------------------------------------------------------------------------
merge into RAW.DIM_PLATFORM tgt
using (
    select * from values
        ('VW-2.1', 'Vayuveda VW-2.1', 2.10, 3.0, 11.5, 25.0, 100.0, 80.0),
        ('VW-3.0', 'Vayuveda VW-3.0', 3.00, 3.0, 12.0, 25.0, 144.0, 100.0)
    as s(id, name, mw, cut_in, rated, cut_out, rotor, hub)
) src
on tgt.platform_id = src.id
when not matched then insert (platform_id, platform_name, rated_power_mw, cut_in_speed_ms, rated_speed_ms, cut_out_speed_ms, rotor_diameter_m, hub_height_m)
    values (src.id, src.name, src.mw, src.cut_in, src.rated, src.cut_out, src.rotor, src.hub);

-- ---------------------------------------------------------------------------
-- Sites — profile §4
-- ---------------------------------------------------------------------------
merge into RAW.DIM_SITE tgt
using (
    select * from values
        ('GJ-KCH', 'Kutch Ridge Wind Park',        'Gujarat',     'West',  7.5, 'Coastal salt, dust',                       28),
        ('TN-TVL', 'Tirunelveli Coast Wind Park',   'Tamil Nadu',  'South', 7.0, 'Coastal salinity',                         22),
        ('KA-CTD', 'Chitradurga Plateau Wind Park', 'Karnataka',   'South', 6.5, 'Plateau, moderate',                        18),
        ('MH-STR', 'Satara Ghats Wind Park',        'Maharashtra', 'West',  6.8, 'Monsoon wind and lightning',               14),
        ('RJ-JSM', 'Jaisalmer Desert Wind Park',    'Rajasthan',   'North', 8.0, 'Dust and extreme heat',                    12),
        ('KA-GDG', 'Gadag Wind Park',               'Karnataka',   'South', 6.0, 'Moderate',                                  6)
    as s(code, name, state, region, wind, stressor, count)
) src
on tgt.site_code = src.code
when not matched then insert (site_code, site_name, state, region, mean_wind_speed, site_stressor, turbine_count)
    values (src.code, src.name, src.state, src.region, src.wind, src.stressor, src.count);

-- ---------------------------------------------------------------------------
-- Contracts — profile §2 (one per site)
-- ---------------------------------------------------------------------------
merge into RAW.DIM_CONTRACT tgt
using (
    select * from values
        ('CTR-GJ-KCH', 'GJ-KCH', 'IPP',                    '2023-01-01'::date, 10, 95.00, 97.00, 50000.00, 200.0),
        ('CTR-TN-TVL', 'TN-TVL', 'C&I (group captive)',     '2016-06-01'::date, 10, 95.00, 97.00, 50000.00, 200.0),
        ('CTR-KA-CTD', 'KA-CTD', 'IPP',                    '2022-04-01'::date, 10, 95.00, 97.00, 50000.00, 200.0),
        ('CTR-MH-STR', 'MH-STR', 'C&I (captive)',          '2017-07-01'::date, 10, 95.00, 97.00, 50000.00, 200.0),
        ('CTR-RJ-JSM', 'RJ-JSM', 'Public-sector utility',  '2024-03-01'::date, 10, 95.00, 97.00, 50000.00, 200.0),
        ('CTR-KA-GDG', 'KA-GDG', 'C&I',                    '2019-01-01'::date, 10, 95.00, 97.00, 50000.00, 200.0)
    as s(id, site, ctype, start_dt, dur, g12, g3, ld, maint_hrs)
) src
on tgt.contract_id = src.id
when not matched then insert (contract_id, site_code, customer_type, start_date, duration_years, guarantee_yr1_2_pct, guarantee_yr3_plus_pct, ld_rate_per_turbine_per_pct, scheduled_maint_hours_yr)
    values (src.id, src.site, src.ctype, src.start_dt, src.dur, src.g12, src.g3, src.ld, src.maint_hrs);

-- ---------------------------------------------------------------------------
-- Exclusion classes — data-model.md §4
-- ---------------------------------------------------------------------------
merge into RAW.DIM_EXCLUSION_CLASS tgt
using (
    select * from values
        ('GRID',       'Grid Outage',          'Grid or substation failure; not counted against provider'),
        ('FORCE_MAJ',  'Force Majeure',        'Natural disaster, extreme weather beyond design limits'),
        ('BOP',        'Balance of Plant',      'Non-turbine electrical infrastructure failure'),
        ('CURTAIL',    'Curtailment',           'Grid operator instruction to reduce output'),
        ('SCHED_MAINT','Scheduled Maintenance', 'Within the annual scheduled maintenance hour allowance')
    as s(code, name, descr)
) src
on tgt.exclusion_class_code = src.code
when not matched then insert (exclusion_class_code, exclusion_class_name, description)
    values (src.code, src.name, src.descr);

-- ---------------------------------------------------------------------------
-- Turbines — 100 turbines across 6 sites, per profile §4
-- Site assignments: GJ-KCH=28, TN-TVL=22, KA-CTD=18, MH-STR=14, RJ-JSM=12, KA-GDG=6
-- Platform: GJ-KCH/KA-CTD/RJ-JSM = VW-3.0; TN-TVL/MH-STR/KA-GDG = VW-2.1
-- Commissioned dates spread across the years shown in the profile.
-- ---------------------------------------------------------------------------

merge into RAW.DIM_TURBINE tgt
using (
with site_turbines as (
    select
        s.site_code,
        s.platform_id,
        s.region,
        s.state,
        row_number() over (partition by s.site_code order by seq4()) as seq,
        s.start_date
    from (
        select 'GJ-KCH' as site_code, 'VW-3.0' as platform_id, 'West' as region, 'Gujarat' as state, '2023-03-01'::date as start_date, 28 as cnt union all
        select 'TN-TVL', 'VW-2.1', 'South', 'Tamil Nadu', '2016-06-01'::date, 22 union all
        select 'KA-CTD', 'VW-3.0', 'South', 'Karnataka', '2022-04-01'::date, 18 union all
        select 'MH-STR', 'VW-2.1', 'West', 'Maharashtra', '2017-07-01'::date, 14 union all
        select 'RJ-JSM', 'VW-3.0', 'North', 'Rajasthan', '2024-03-01'::date, 12 union all
        select 'KA-GDG', 'VW-2.1', 'South', 'Karnataka', '2019-01-15'::date, 6
    ) s,
    table(generator(rowcount => 28)) g
    qualify row_number() over (partition by s.site_code order by seq4()) <= s.cnt
)
select
    site_code || '-T' || lpad(seq::varchar, 2, '0') as turbine_id,
    site_code,
    platform_id,
    dateadd(day, (seq - 1) * 30, start_date) as commissioned_date,
    'vws/' || lower(region) || '/' || lower(replace(state, ' ', '-')) || '/' || lower(site_code) || '/t' || lpad(seq::varchar, 2, '0') as uns_path
from site_turbines
) src
on tgt.turbine_id = src.turbine_id
when not matched then insert (turbine_id, site_code, platform_id, commissioned_date, uns_path)
    values (src.turbine_id, src.site_code, src.platform_id, src.commissioned_date, src.uns_path);

-- ---------------------------------------------------------------------------
-- Components — 10 per turbine = 1,000 total, per profile §5
-- ---------------------------------------------------------------------------
merge into RAW.DIM_COMPONENT tgt
using (
select
    t.turbine_id || '-' || cc.component_class_code as component_id,
    t.turbine_id,
    cc.component_class_code,
    cc.component_class_code || '-' || right(year(t.commissioned_date)::varchar, 2) || '-' ||
        lpad(row_number() over (partition by cc.component_class_code order by t.turbine_id)::varchar, 5, '0') as installed_serial,
    t.commissioned_date as install_date,
    t.uns_path || '/' || lower(cc.component_class_code) as uns_path
from RAW.DIM_TURBINE t
cross join RAW.DIM_COMPONENT_CLASS cc
) src
on tgt.component_id = src.component_id
when not matched then insert (component_id, turbine_id, component_class_code, installed_serial, install_date, uns_path)
    values (src.component_id, src.turbine_id, src.component_class_code, src.installed_serial, src.install_date, src.uns_path);

-- ---------------------------------------------------------------------------
-- Initial genealogy — every component starts with its original serial
-- ---------------------------------------------------------------------------
merge into RAW.DIM_COMPONENT_GENEALOGY tgt
using (
    select
        component_id,
        installed_serial as serial_number,
        install_date::timestamp_ntz as valid_from,
        null as valid_to,
        'INITIAL_INSTALL' as event_type
    from RAW.DIM_COMPONENT
) src
on tgt.component_id = src.component_id and tgt.serial_number = src.serial_number
when not matched then insert (component_id, serial_number, valid_from, valid_to, event_type)
    values (src.component_id, src.serial_number, src.valid_from, src.valid_to, src.event_type);

-- ---------------------------------------------------------------------------
-- Signals — per profile §5, key signals for each component type
-- Approximately 40 signals per turbine (varies by platform).
-- ---------------------------------------------------------------------------
merge into RAW.DIM_SIGNAL tgt
using (
with signal_defs as (
    -- Turbine-level environmental/operational signals
    select 'WIND_SPEED'     as name, 'ENVIRONMENTAL' as stype, 'TURBINE' as scope, null as cc, 'm/s'  as unit, 0 as lo, 30 as hi union all
    select 'WIND_DIR',       'ENVIRONMENTAL', 'TURBINE', null, 'deg',  0, 360 union all
    select 'AMBIENT_TEMP',   'ENVIRONMENTAL', 'TURBINE', null, '°C',  -10, 50 union all
    select 'NACELLE_TEMP',   'ENVIRONMENTAL', 'TURBINE', null, '°C',  10, 60 union all
    select 'ACTIVE_POWER',   'OPERATIONAL',   'TURBINE', null, 'kW',  0, 3000 union all
    select 'REACTIVE_POWER', 'OPERATIONAL',   'TURBINE', null, 'kVAr', -500, 500 union all
    select 'ROTOR_RPM',      'OPERATIONAL',   'TURBINE', null, 'rpm', 0, 20 union all
    select 'GEN_RPM',        'OPERATIONAL',   'TURBINE', null, 'rpm', 0, 1800 union all
    -- MSB signals
    select 'VIB_MSB',        'CMS',           'COMPONENT', 'MSB', 'mm/s',  0, 10 union all
    select 'TEMP_MSB',       'TEMPERATURE',   'COMPONENT', 'MSB', '°C',   20, 80 union all
    -- GBX signals (5 vibration + temps + oil)
    select 'VIB_GBX_PL1',    'CMS',           'COMPONENT', 'GBX', 'mm/s',  0, 10 union all
    select 'VIB_GBX_PL2',    'CMS',           'COMPONENT', 'GBX', 'mm/s',  0, 10 union all
    select 'VIB_GBX_IMS',    'CMS',           'COMPONENT', 'GBX', 'mm/s',  0, 10 union all
    select 'VIB_GBX_HSS',    'CMS',           'COMPONENT', 'GBX', 'mm/s',  0, 12 union all
    select 'VIB_GBX_HSS_BE', 'CMS',           'COMPONENT', 'GBX', 'mm/s',  0, 12 union all
    select 'TEMP_GBX_OIL',   'TEMPERATURE',   'COMPONENT', 'GBX', '°C',   30, 80 union all
    select 'TEMP_GBX_HSS',   'TEMPERATURE',   'COMPONENT', 'GBX', '°C',   30, 85 union all
    select 'OIL_PRESSURE',   'OPERATIONAL',   'COMPONENT', 'GBX', 'bar',  2, 6 union all
    select 'OIL_PARTICLE',   'CMS',           'COMPONENT', 'GBX', 'ppm',  0, 100 union all
    -- GEN signals
    select 'VIB_GEN_DE',     'CMS',           'COMPONENT', 'GEN', 'mm/s',  0, 8 union all
    select 'VIB_GEN_NDE',    'CMS',           'COMPONENT', 'GEN', 'mm/s',  0, 8 union all
    select 'TEMP_GEN_WIND',  'TEMPERATURE',   'COMPONENT', 'GEN', '°C',   30, 120 union all
    select 'TEMP_GEN_BEAR',  'TEMPERATURE',   'COMPONENT', 'GEN', '°C',   30, 90 union all
    -- PIT signals
    select 'PITCH_ANGLE',    'OPERATIONAL',   'COMPONENT', 'PIT', 'deg',  0, 90 union all
    select 'PITCH_MOTOR_I',  'OPERATIONAL',   'COMPONENT', 'PIT', 'A',    0, 30 union all
    select 'PITCH_BAT_V',    'OPERATIONAL',   'COMPONENT', 'PIT', 'V',    20, 28 union all
    -- CNV signals
    select 'TEMP_CNV_IGBT',  'TEMPERATURE',   'COMPONENT', 'CNV', '°C',   20, 90 union all
    select 'DC_LINK_V',      'OPERATIONAL',   'COMPONENT', 'CNV', 'V',    500, 750 union all
    select 'TEMP_CNV_COOL',  'TEMPERATURE',   'COMPONENT', 'CNV', '°C',   15, 45 union all
    -- TRF signals
    select 'TEMP_TRF_OIL',   'TEMPERATURE',   'COMPONENT', 'TRF', '°C',   20, 80 union all
    select 'TEMP_TRF_WIND',  'TEMPERATURE',   'COMPONENT', 'TRF', '°C',   30, 120 union all
    select 'LOAD_CURRENT',   'OPERATIONAL',   'COMPONENT', 'TRF', 'A',    0, 500 union all
    -- YAW signals
    select 'YAW_ERROR',      'OPERATIONAL',   'COMPONENT', 'YAW', 'deg',  -15, 15 union all
    select 'YAW_MOTOR_I',    'OPERATIONAL',   'COMPONENT', 'YAW', 'A',    0, 20 union all
    select 'CABLE_TWIST',    'OPERATIONAL',   'COMPONENT', 'YAW', 'turns', -3, 3 union all
    -- NAC signals
    select 'HYD_PRESSURE',   'OPERATIONAL',   'COMPONENT', 'NAC', 'bar',  100, 200 union all
    select 'TEMP_NAC_COOL',  'TEMPERATURE',   'COMPONENT', 'NAC', '°C',   15, 45 union all
    -- TWR signals
    select 'VIB_TWR_TOP',    'CMS',           'COMPONENT', 'TWR', 'mm/s',  0, 5 union all
    select 'TWR_TILT',       'STRUCTURAL',    'COMPONENT', 'TWR', 'deg',  -0.5, 0.5 union all
    -- BLD signals
    select 'LIGHTNING_CNT',  'EVENT',         'COMPONENT', 'BLD', 'count', 0, 10 union all
    select 'VIB_ROTOR_IMBAL','CMS',           'COMPONENT', 'BLD', 'mm/s',  0, 5
)
select
    case
        when sd.scope = 'TURBINE' then t.turbine_id || '-' || sd.name
        else c.component_id || '-' || sd.name
    end as signal_id,
    t.turbine_id,
    case when sd.scope = 'COMPONENT' then c.component_id else null end as component_id,
    sd.name as signal_name,
    sd.stype as signal_type,
    sd.unit,
    sd.lo as normal_range_low,
    sd.hi as normal_range_high
from RAW.DIM_TURBINE t
cross join signal_defs sd
left join RAW.DIM_COMPONENT c
    on c.turbine_id = t.turbine_id
    and c.component_class_code = sd.cc
where sd.scope = 'TURBINE'
   or (sd.scope = 'COMPONENT' and c.component_id is not null)
) src
on tgt.signal_id = src.signal_id
when not matched then insert (signal_id, turbine_id, component_id, signal_name, signal_type, unit, normal_range_low, normal_range_high)
    values (src.signal_id, src.turbine_id, src.component_id, src.signal_name, src.signal_type, src.unit, src.normal_range_low, src.normal_range_high);

-- ---------------------------------------------------------------------------
-- Failure codes — per profile §5 typical failure modes
-- ---------------------------------------------------------------------------
merge into RAW.DIM_FAILURE_CODE tgt
using (
    select * from values
        ('FC-BLD-01', 'Leading edge erosion',           'BLD', 'WEAR'),
        ('FC-BLD-02', 'Lightning damage',               'BLD', 'EVENT'),
        ('FC-BLD-03', 'Blade crack',                    'BLD', 'STRUCTURAL'),
        ('FC-PIT-01', 'Pitch bearing wear',             'PIT', 'WEAR'),
        ('FC-PIT-02', 'Pitch drive fault',              'PIT', 'ELECTRICAL'),
        ('FC-PIT-03', 'Pitch battery failure',           'PIT', 'ELECTRICAL'),
        ('FC-MSB-01', 'Main bearing spalling',          'MSB', 'WEAR'),
        ('FC-MSB-02', 'Main bearing lubrication failure','MSB', 'LUBRICATION'),
        ('FC-GBX-01', 'HSS bearing failure',            'GBX', 'WEAR'),
        ('FC-GBX-02', 'Intermediate bearing failure',    'GBX', 'WEAR'),
        ('FC-GBX-03', 'Gear pitting',                   'GBX', 'WEAR'),
        ('FC-GBX-04', 'Oil cooler failure',             'GBX', 'MECHANICAL'),
        ('FC-GBX-05', 'Oil pump failure',               'GBX', 'MECHANICAL'),
        ('FC-GEN-01', 'Generator bearing failure',      'GEN', 'WEAR'),
        ('FC-GEN-02', 'Winding insulation fault',       'GEN', 'ELECTRICAL'),
        ('FC-GEN-03', 'Slip ring wear',                 'GEN', 'WEAR'),
        ('FC-CNV-01', 'IGBT failure',                   'CNV', 'ELECTRICAL'),
        ('FC-CNV-02', 'Cooling pump failure',            'CNV', 'MECHANICAL'),
        ('FC-TRF-01', 'Transformer overheating',        'TRF', 'THERMAL'),
        ('FC-TRF-02', 'Insulation degradation',         'TRF', 'ELECTRICAL'),
        ('FC-YAW-01', 'Yaw drive wear',                'YAW', 'WEAR'),
        ('FC-YAW-02', 'Yaw brake pad wear',            'YAW', 'WEAR'),
        ('FC-NAC-01', 'Hydraulic leak',                 'NAC', 'MECHANICAL'),
        ('FC-NAC-02', 'Coolant pump failure',            'NAC', 'MECHANICAL'),
        ('FC-TWR-01', 'Bolt loosening',                 'TWR', 'STRUCTURAL'),
        ('FC-TWR-02', 'Corrosion',                      'TWR', 'WEAR')
    as s(code, name, cc, cat)
) src
on tgt.failure_code = src.code
when not matched then insert (failure_code, failure_name, component_class_code, failure_category)
    values (src.code, src.name, src.cc, src.cat);

-- ---------------------------------------------------------------------------
-- Alarm codes — invented code list per Q-44, with safety-critical flags
-- Covers all four sources: SCADA, CMS, GRID, DQ (data quality)
-- ---------------------------------------------------------------------------
merge into RAW.DIM_ALARM_CODE tgt
using (
    select * from values
        -- SCADA alarms
        ('SA-OT-001', 'SCADA', 'Gearbox over-temperature',        'WARNING',  'GBX', false, true,  'Gearbox oil or bearing temperature above warning threshold'),
        ('SA-OT-002', 'SCADA', 'Generator winding over-temp',     'WARNING',  'GEN', false, true,  'Generator winding temperature above warning threshold'),
        ('SA-OT-003', 'SCADA', 'Generator bearing over-temp',     'WARNING',  'GEN', false, true,  'Generator bearing temperature above warning threshold'),
        ('SA-OT-004', 'SCADA', 'Converter IGBT over-temp',        'WARNING',  'CNV', false, true,  'IGBT module temperature above threshold'),
        ('SA-OT-005', 'SCADA', 'Transformer over-temp',           'WARNING',  'TRF', false, false, 'Transformer oil temperature above threshold'),
        ('SA-VB-001', 'SCADA', 'Nacelle vibration high',          'ALARM',    'NAC', false, false, 'Tower-top vibration exceeds limit'),
        ('SA-VB-002', 'SCADA', 'Rotor imbalance detected',        'ALARM',    'BLD', false, false, 'Rotor imbalance detected from nacelle vibration'),
        ('SA-PT-001', 'SCADA', 'Pitch system fault',              'ALARM',    'PIT', false, true,  'Pitch drive or motor fault'),
        ('SA-PT-002', 'SCADA', 'Pitch battery low voltage',       'WARNING',  'PIT', false, false, 'Backup battery below threshold'),
        ('SA-YW-001', 'SCADA', 'Yaw error persistent',            'WARNING',  'YAW', false, false, 'Sustained yaw misalignment above tolerance'),
        ('SA-YW-002', 'SCADA', 'Cable twist limit',               'ALARM',    'YAW', true,  false, 'Cable twist approaching limit — safety stop'),
        ('SA-GR-001', 'SCADA', 'Grid fault trip',                 'TRIP',     null,  false, true,  'Grid voltage or frequency outside tolerance'),
        ('SA-GR-002', 'SCADA', 'Grid under-voltage',              'WARNING',  null,  false, true,  'Grid voltage below lower threshold'),
        ('SA-HY-001', 'SCADA', 'Hydraulic pressure low',          'WARNING',  'NAC', false, false, 'Hydraulic system pressure below threshold'),
        ('SA-EM-001', 'SCADA', 'Emergency stop activated',        'TRIP',     null,  true,  false, 'Manual or automatic emergency stop'),
        ('SA-SP-001', 'SCADA', 'Overspeed protection trip',       'TRIP',     null,  true,  false, 'Rotor overspeed safety system activated'),
        -- CMS threshold alarms
        ('CM-VB-001', 'CMS',   'GBX HSS vibration high',         'WARNING',  'GBX', false, false, 'HSS bearing band energy above warning threshold'),
        ('CM-VB-002', 'CMS',   'GBX HSS vibration alarm',        'ALARM',    'GBX', false, false, 'HSS bearing band energy above alarm threshold'),
        ('CM-VB-003', 'CMS',   'GBX IMS vibration high',         'WARNING',  'GBX', false, false, 'Intermediate shaft band energy above warning'),
        ('CM-VB-004', 'CMS',   'Generator DE bearing high',      'WARNING',  'GEN', false, false, 'Generator drive-end bearing vibration above warning'),
        ('CM-VB-005', 'CMS',   'Main bearing vibration high',    'WARNING',  'MSB', false, false, 'Main bearing vibration above warning'),
        ('CM-VB-006', 'CMS',   'Main bearing vibration alarm',   'ALARM',    'MSB', false, false, 'Main bearing vibration above alarm threshold'),
        ('CM-OD-001', 'CMS',   'Oil debris count high',          'WARNING',  'GBX', false, false, 'Particle count above warning threshold'),
        ('CM-OD-002', 'CMS',   'Oil debris count alarm',         'ALARM',    'GBX', false, false, 'Particle count above alarm threshold — gear or bearing damage likely'),
        -- GRID / BOP alarms
        ('GR-UV-001', 'GRID',  'Grid under-voltage event',       'EVENT',    null,  false, false, 'Grid voltage dip detected at substation'),
        ('GR-OF-001', 'GRID',  'Grid over-frequency',            'EVENT',    null,  false, false, 'Grid frequency above tolerance'),
        ('GR-FT-001', 'GRID',  'Grid fault — site-wide',         'TRIP',     null,  false, true,  'Site-wide grid outage from external fault'),
        ('GR-CT-001', 'GRID',  'Curtailment instruction',        'EVENT',    null,  false, false, 'Grid operator curtailment instruction'),
        -- Data quality alarms (source 4 — platform-generated)
        ('DQ-ST-001', 'DQ',    'SCADA signal stale',             'WARNING',  null,  false, false, 'SCADA signal not updated within expected window'),
        ('DQ-RI-001', 'DQ',    'Referential integrity violation', 'ALARM',   null,  false, false, 'FK violation detected in data pipeline'),
        ('DQ-RN-001', 'DQ',    'Row count anomaly',              'WARNING',  null,  false, false, 'Unexpected row count change in a fact table')
    as s(code, source, name, severity, cc, safety, autoreset, descr)
) src
on tgt.alarm_code = src.code
when not matched then insert (alarm_code, alarm_source, alarm_name, severity, component_class_code, is_safety_critical, auto_reset_eligible, description)
    values (src.code, src.source, src.name, src.severity, src.cc, src.safety, src.autoreset, src.descr);

-- ---------------------------------------------------------------------------
-- Crews — illustrative, per profile §6
-- ---------------------------------------------------------------------------
merge into RAW.DIM_CREW tgt
using (
    select * from values
        ('CRW-S01', 'South Alpha',     'KA-CTD', 'South', 2),
        ('CRW-S02', 'South Beta',      'TN-TVL', 'South', 2),
        ('CRW-S03', 'South Gamma',     'KA-GDG', 'South', 1),
        ('CRW-W01', 'West Alpha',      'GJ-KCH', 'West',  2),
        ('CRW-W02', 'West Beta',       'MH-STR', 'West',  2),
        ('CRW-N01', 'North Alpha',     'RJ-JSM', 'North', 2),
        ('CRW-CR01','Crane Team South', null,     'South', 1),
        ('CRW-CR02','Crane Team West',  null,     'West',  1)
    as s(id, name, site, region, max_per_day)
) src
on tgt.crew_id = src.id
when not matched then insert (crew_id, crew_name, base_site_code, region, max_turbines_per_day)
    values (src.id, src.name, src.site, src.region, src.max_per_day);

-- ---------------------------------------------------------------------------
-- Parts catalogue — key spares per component class
-- ---------------------------------------------------------------------------
merge into RAW.DIM_PART tgt
using (
    select * from values
        ('PT-GBX-BEAR-HSS',  'Gearbox HSS bearing',           'GBX', 60,  250000.00, false),
        ('PT-GBX-BEAR-IMS',  'Gearbox intermediate bearing',  'GBX', 60,  180000.00, false),
        ('PT-GBX-FULL',      'Complete gearbox assembly',      'GBX', 120, 3500000.00, true),
        ('PT-GBX-OIL-COOL',  'Gearbox oil cooler',            'GBX', 14,  45000.00,  false),
        ('PT-GEN-BEAR-DE',   'Generator DE bearing',           'GEN', 30,  85000.00,  false),
        ('PT-GEN-BEAR-NDE',  'Generator NDE bearing',          'GEN', 30,  85000.00,  false),
        ('PT-GEN-STATOR',    'Generator stator',               'GEN', 90,  1800000.00, true),
        ('PT-MSB-BEAR',      'Main bearing',                    'MSB', 90,  600000.00, true),
        ('PT-PIT-BEAR',      'Pitch bearing',                   'PIT', 75,  350000.00, true),
        ('PT-PIT-MOTOR',     'Pitch motor',                     'PIT', 21,  65000.00,  false),
        ('PT-PIT-BAT',       'Pitch battery pack',              'PIT', 7,   25000.00,  false),
        ('PT-CNV-IGBT',      'Converter IGBT module',           'CNV', 14,  120000.00, false),
        ('PT-CNV-PUMP',      'Converter cooling pump',          'CNV', 7,   15000.00,  false),
        ('PT-YAW-DRIVE',     'Yaw drive unit',                  'YAW', 21,  75000.00,  false),
        ('PT-YAW-PAD',       'Yaw brake pad set',              'YAW', 7,   8000.00,   false),
        ('PT-BLD-TIP',       'Blade tip repair kit',            'BLD', 14,  45000.00,  false),
        ('PT-BLD-FULL',      'Complete blade',                   'BLD', 180, 2500000.00, true),
        ('PT-NAC-PUMP-HYD',  'Hydraulic pump',                  'NAC', 14,  35000.00,  false),
        ('PT-TRF-FULL',      'Unit transformer',                'TRF', 90,  800000.00, true)
    as s(pn, name, cc, lead, cost, crane)
) src
on tgt.part_number = src.pn
when not matched then insert (part_number, part_name, component_class_code, lead_time_days, unit_cost_inr, requires_crane)
    values (src.pn, src.name, src.cc, src.lead, src.cost, src.crane);

-- ---------------------------------------------------------------------------
-- Stock — initial inventory at key locations
-- ---------------------------------------------------------------------------
merge into RAW.DIM_STOCK tgt
using (
    select
        'STK-' || w.loc || '-' || p.part_number as stock_id,
        p.part_number,
        w.loc as warehouse_location,
        case
            when p.requires_crane then uniform(0, 1, random())
            else uniform(1, 4, random())
        end as qty_on_hand,
        0 as qty_reserved,
        current_timestamp()::timestamp_ntz as last_updated
    from RAW.DIM_PART p
    cross join (
        select 'Coimbatore Central' as loc union all
        select 'Chitradurga Site' union all
        select 'Kutch Site' union all
        select 'Jaisalmer Site'
    ) w
) src
on tgt.stock_id = src.stock_id
when not matched then insert (stock_id, part_number, warehouse_location, quantity_on_hand, quantity_reserved, last_updated)
    values (src.stock_id, src.part_number, src.warehouse_location, src.qty_on_hand, src.qty_reserved, src.last_updated);
