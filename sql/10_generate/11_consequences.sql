-- =============================================================================
-- 10_generate / 11 — consequences: work orders, parts, genealogy
--                                                              STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-7 (matching work orders), US-10 (genealogy tracked)
-- Proves     : T-7 (every seeded failure has a corrective work order),
--              and the referential-integrity half of T-1
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §2 stage 6, §5
-- Parameter  : <% database %>
--
-- Stage 6. Every seeded failure produces a corrective work order, a part issue
-- and a genealogy event, because a sensor record and a maintenance history that
-- disagree is the reference solution's defect T-7 exists to prevent.
--
-- TECHNICIAN NOTES — THE SPECIFIC TRAP (§5). The reference solution's
-- TECHNICIAN_NOTES looked like free text and was in fact CASE MOD(asset_id, 6),
-- producing 19 distinct strings across ~2,000 rows: a low-cardinality
-- categorical column in a VARCHAR costume, over which nothing performed
-- retrieval. Here a note is composed from FOUR INDEPENDENTLY DRAWN parts — a
-- symptom, an action, a part observation and a closing remark — each salted
-- differently, plus a measured figure. That is >10,000 combinations before the
-- numbers, and the numbers make near-duplicates rare.
--
-- Two deliberate touches of realism: notes use inconsistent component naming and
-- field abbreviations, and a small fraction CONTRADICT the structured failure
-- code, because field notes do. Anything reading these must treat them as
-- corroborating evidence, never as ground truth — which is why the retrieval
-- story rests on real document files (CMP-11), not on this column.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure GEN.SP_GENERATE_CONSEQUENCES(
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
    n_corrective integer;
    n_pm         integer;
    n_insp       integer;
    n_parts      integer;
    n_geneal     integer;
begin
    delete from RAW.FCT_PART_MOVEMENT where movement_date between :window_start and :window_end;
    delete from RAW.FCT_WORK_ORDER    where created_date  between :window_start and :window_end;
    delete from RAW.DIM_COMPONENT_GENEALOGY
    where event_type <> 'INITIAL_INSTALL'
      and valid_from between :window_start and :window_end;

    -- ---- the note vocabulary ---------------------------------------------
    create or replace temporary table GEN.GEN_TMP_NOTE_PART as
    select * from values
        (1, 'symptom', 'loud whine from the nacelle on ramp-up'),
        (2, 'symptom', 'intermittent rumble, worse above 1200 rpm'),
        (3, 'symptom', 'high vib trend flagged by CMS two weeks back'),
        (4, 'symptom', 'oil temp creeping up, ~8C above the sister unit'),
        (5, 'symptom', 'metallic knock audible at the tower base'),
        (6, 'symptom', 'repeated trips, resets itself each time'),
        (7, 'symptom', 'grinding on yaw movement, operator called it in'),
        (8, 'symptom', 'smell of hot oil in the nacelle'),
        (9, 'symptom', 'unit derating on its own, no alarm logged'),
        (10, 'symptom', 'vibration alarm at 04:10, turbine stopped itself'),
        (11, 'symptom', 'pitch response sluggish on one blade'),
        (12, 'symptom', 'converter cabinet running hot to the touch'),
        (1, 'action', 'stripped the HS stage and inspected'),
        (2, 'action', 'borescope through the inspection port'),
        (3, 'action', 'replaced brg and re-torqued to spec'),
        (4, 'action', 'drained oil, flushed, refilled w/ fresh charge'),
        (5, 'action', 'swapped the sensor and re-ran the baseline'),
        (6, 'action', 'crane mobilised, full assembly exchange'),
        (7, 'action', 'cleaned and re-greased, no parts used'),
        (8, 'action', 'tightened the mounting bolts, torque checked'),
        (9, 'action', 'replaced the cooling pump and bled the circuit'),
        (10, 'action', 'reseated the connector, contact was corroded'),
        (11, 'action', 'aligned the coupling, ran it up under load'),
        (12, 'action', 'temporary fix only, needs a proper repair next visit'),
        (1, 'part_obs', 'inner race spalled, visible pitting over ~30% of track'),
        (2, 'part_obs', 'debris in the oil filter, fine metallic'),
        (3, 'part_obs', 'gear flank showed micropitting, early stage'),
        (4, 'part_obs', 'seal hardened and cracked, was weeping'),
        (5, 'part_obs', 'no obvious damage found on strip-down'),
        (6, 'part_obs', 'cage worn through in two places'),
        (7, 'part_obs', 'winding insulation discoloured near the slot exit'),
        (8, 'part_obs', 'IGBT module showed thermal fatigue at the solder'),
        (9, 'part_obs', 'brake pads down to ~2mm, below limit'),
        (10, 'part_obs', 'lubricant had carbonised, almost no film left'),
        (11, 'part_obs', 'bolt thread galled, replaced the fastener set'),
        (12, 'part_obs', 'part looked serviceable, refitted it'),
        (1, 'closing', 'ran up fine after, vib back to baseline'),
        (2, 'closing', 'monitor on next visit'),
        (3, 'closing', 'recommend shortening the inspection interval here'),
        (4, 'closing', 'second unit at this site showing the same pattern'),
        (5, 'closing', 'parts ordered for the sister turbine as a precaution'),
        (6, 'closing', 'handed back to ops, running at full output'),
        (7, 'closing', 'still not happy with it, flagged for review'),
        (8, 'closing', 'no further action needed'),
        (9, 'closing', 'weather cut the visit short, finished next day'),
        (10, 'closing', 'crane slot was the long pole, repair itself was quick'),
        (11, 'closing', 'suspect a batch issue, serials noted for the OEM'),
        (12, 'closing', 'customer informed, they were fine with the downtime')
    as v(idx, slot, text);

    -- =======================================================================
    -- CORRECTIVE work orders — one per seeded failure. T-7.
    -- =======================================================================
    insert into RAW.FCT_WORK_ORDER (
        work_order_id, turbine_id, component_id, work_order_type, failure_code,
        cause_description, remedy_description, technician_notes, status, priority,
        created_date, scheduled_date, completed_date, downtime_hours, labour_hours,
        crew_id, requires_crane
    )
    select
        'WO-C-' || replace(f.component_id, '-', '') || '-' || to_varchar(f.failure_ts, 'YYYYMMDD'),
        f.turbine_id,
        f.component_id,
        'CORRECTIVE',
        f.failure_code,
        fc.failure_name || ' on ' || cc.component_class_name
            || ' (' || fc.failure_category || ')',
        case when pt.requires_crane then 'Component exchange with crane support'
             else 'Component repair or exchange in situ' end,
        -- four independent draws, plus a measured figure
        initcap(ns.text) || '. ' || na.text || '; ' || np.text || '. '
            || case
                   when GEN.FN_RAND(f.component_id, :seed || 'num') < 0.5
                   then 'peak vib ' || round(3.0 + 9.0 * GEN.FN_RAND(f.component_id, :seed || 'v'), 1) || ' mm/s. '
                   else 'oil temp ' || round(62.0 + 22.0 * GEN.FN_RAND(f.component_id, :seed || 't'), 0) || 'C at the time. '
               end
            || nc.text
            -- a small share disagree with the structured code, because field
            -- notes do. Anything treating these as ground truth is wrong.
            || case
                   when GEN.FN_RAND(f.component_id, :seed || 'contra') < 0.06
                   then ' NB coded as ' || f.failure_code || ' but I think it started upstream.'
                   else ''
               end,
        case when f.repair_ts <= :window_end then 'CLOSED' else 'IN_PROGRESS' end,
        case
            when cc.is_drivetrain and pt.requires_crane then 'P1'
            when cc.is_drivetrain                       then 'P2'
            else 'P3'
        end,
        f.failure_ts,
        dateadd(hour, 6 + floor(48 * GEN.FN_RAND(f.component_id, :seed || 'sch')), f.failure_ts),
        case when f.repair_ts <= :window_end then f.repair_ts end,
        round(datediff(hour, f.failure_ts, f.repair_ts), 2),
        round(4.0 + 44.0 * GEN.FN_RAND(f.component_id, :seed || 'lab'), 2),
        cr.crew_id,
        coalesce(pt.requires_crane, false)
    from GEN.GEN_FAILURE_EVENT f
    join RAW.DIM_FAILURE_CODE fc    on fc.failure_code = f.failure_code
    join RAW.DIM_COMPONENT_CLASS cc on cc.component_class_code = f.component_class_code
    join RAW.DIM_TURBINE t          on t.turbine_id = f.turbine_id
    left join (
        select component_class_code, max(requires_crane) as requires_crane
        from RAW.DIM_PART group by component_class_code
    ) pt on pt.component_class_code = f.component_class_code
    -- nearest crew: same site if there is one, else the region's
    left join RAW.DIM_CREW cr
        on cr.crew_id = (
            select min(c2.crew_id) from RAW.DIM_CREW c2
            join RAW.DIM_SITE s2 on s2.site_code = t.site_code
            where coalesce(c2.base_site_code, s2.site_code) = t.site_code
        )
    join GEN.GEN_TMP_NOTE_PART ns
        on ns.slot = 'symptom'  and ns.idx = 1 + floor(12 * GEN.FN_RAND(f.component_id, :seed || 'n1'))
    join GEN.GEN_TMP_NOTE_PART na
        on na.slot = 'action'   and na.idx = 1 + floor(12 * GEN.FN_RAND(f.component_id, :seed || 'n2'))
    join GEN.GEN_TMP_NOTE_PART np
        on np.slot = 'part_obs' and np.idx = 1 + floor(12 * GEN.FN_RAND(f.component_id, :seed || 'n3'))
    join GEN.GEN_TMP_NOTE_PART nc
        on nc.slot = 'closing'  and nc.idx = 1 + floor(12 * GEN.FN_RAND(f.component_id, :seed || 'n4'))
    where f.failure_ts between :window_start and :window_end;

    n_corrective := sqlrowcount;

    -- =======================================================================
    -- PREVENTIVE work orders — from the scheduled maintenance intervals
    -- =======================================================================
    insert into RAW.FCT_WORK_ORDER (
        work_order_id, turbine_id, component_id, work_order_type, failure_code,
        cause_description, remedy_description, technician_notes, status, priority,
        created_date, scheduled_date, completed_date, downtime_hours, labour_hours,
        crew_id, requires_crane
    )
    select
        'WO-P-' || replace(s.turbine_id, '-', '') || '-' || to_varchar(s.state_start, 'YYYYMMDD'),
        s.turbine_id,
        s.turbine_id || '-NAC',
        'PREVENTIVE',
        null,
        'Scheduled maintenance per PM plan',
        'Inspection, lubrication, torque checks, filter change',
        'Routine visit. ' || na.text || '; ' || nc.text,
        'CLOSED',
        'P4',
        s.state_start,
        s.state_start,
        s.state_end,
        round(datediff(minute, s.state_start, s.state_end) / 60.0, 2),
        round(6.0 + 6.0 * GEN.FN_RAND(s.turbine_id || to_varchar(s.state_start, 'YYYYMMDD'), :seed || 'pmlab'), 2),
        null,
        false
    from RAW.FCT_TURBINE_STATE s
    join GEN.GEN_TMP_NOTE_PART na
        on na.slot = 'action'  and na.idx = 1 + floor(12 * GEN.FN_RAND(s.turbine_id || to_varchar(s.state_start, 'YYYYMMDD'), :seed || 'p1'))
    join GEN.GEN_TMP_NOTE_PART nc
        on nc.slot = 'closing' and nc.idx = 1 + floor(12 * GEN.FN_RAND(s.turbine_id || to_varchar(s.state_start, 'YYYYMMDD'), :seed || 'p2'))
    where s.exclusion_class_code = 'SCHED_MAINT'
      and s.state_start between :window_start and :window_end;

    n_pm := sqlrowcount;

    -- =======================================================================
    -- INSPECTION work orders — raised off CMS alarms, one per component per
    -- month in which the condition was flagged.
    --
    -- This is the "we looked because the data told us to" population, and it is
    -- what a predictive programme is supposed to produce. Scoped to WARNING as
    -- well as ALARM level and grouped by month: an earlier version took only
    -- alarm-level crossings on components that never failed, and produced ONE
    -- inspection order in six months against the ~1,500 total work orders
    -- data-sources §3 budgets. A maintenance history with no inspections in it
    -- describes a reactive programme, which is the opposite of the claim.
    -- =======================================================================
    insert into RAW.FCT_WORK_ORDER (
        work_order_id, turbine_id, component_id, work_order_type, failure_code,
        cause_description, remedy_description, technician_notes, status, priority,
        created_date, scheduled_date, completed_date, downtime_hours, labour_hours,
        crew_id, requires_crane
    )
    with alarm_pick as (
        select
            a.turbine_id,
            a.component_id,
            date_trunc('month', a.alarm_start) as month_start,
            min(a.alarm_start)                 as first_alarm,
            count(*)                           as n_alarms,
            max(case when a.alarm_code in ('CM-VB-002', 'CM-VB-006') then 1 else 0 end) as reached_alarm_level
        from RAW.FCT_ALARM_NORMALISED a
        where a.alarm_source = 'CMS'
          and a.alarm_start between :window_start and :window_end
          and a.component_id is not null
        group by 1, 2, 3
    )
    select
        'WO-I-' || replace(ap.component_id, '-', '') || '-' || to_varchar(ap.month_start, 'YYYYMM'),
        ap.turbine_id,
        ap.component_id,
        'INSPECTION',
        null,
        case when ap.reached_alarm_level = 1
             then 'CMS alarm level exceeded on ' || ap.n_alarms || ' day(s) — condition-based inspection'
             else 'CMS warning level exceeded on ' || ap.n_alarms || ' day(s) — trend review' end,
        'Inspection and trend review; no exchange performed',
        'Called out by the vib trend. ' || na.text || '; ' || np.text || ' ' || nc.text,
        'CLOSED',
        case when ap.reached_alarm_level = 1 then 'P3' else 'P4' end,
        ap.first_alarm,
        dateadd(day, 2 + floor(12 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'isch')), ap.first_alarm),
        dateadd(day, 3 + floor(14 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'idon')), ap.first_alarm),
        round(2.0 + 5.0 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'idt'), 2),
        round(3.0 + 7.0 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'ilab'), 2),
        null,
        false
    from alarm_pick ap
    join GEN.GEN_TMP_NOTE_PART na
        on na.slot = 'action'   and na.idx = 1 + floor(12 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'i1'))
    join GEN.GEN_TMP_NOTE_PART np
        on np.slot = 'part_obs' and np.idx = 1 + floor(12 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'i2'))
    join GEN.GEN_TMP_NOTE_PART nc
        on nc.slot = 'closing'  and nc.idx = 1 + floor(12 * GEN.FN_RAND(ap.component_id || to_varchar(ap.month_start, 'YYYYMM'), :seed || 'i3'))
    -- but not where we already raised a corrective order on that component that
    -- month: the failure supersedes the inspection.
    where not exists (
        select 1 from GEN.GEN_FAILURE_EVENT f
        where f.component_id = ap.component_id
          and date_trunc('month', f.failure_ts) = ap.month_start
    );

    n_insp := sqlrowcount;

    -- =======================================================================
    -- PART MOVEMENTS — an issue per corrective order
    -- =======================================================================
    insert into RAW.FCT_PART_MOVEMENT (
        movement_id, work_order_id, part_number, stock_id, movement_type,
        quantity, movement_date
    )
    select
        -- MOVEMENT_ID is varchar(30); including the part number overflowed it.
        -- One part is issued per corrective order, so the order key is unique.
        'PM-' || replace(w.work_order_id, 'WO-C-', ''),
        w.work_order_id,
        p.part_number,
        st.stock_id,
        'ISSUE',
        1,
        coalesce(w.completed_date, w.scheduled_date)
    from RAW.FCT_WORK_ORDER w
    join RAW.DIM_COMPONENT c on c.component_id = w.component_id
    -- cheapest part for the class that is not the whole assembly
    join RAW.DIM_PART p
        on p.component_class_code = c.component_class_code
       and p.part_number = (
            select min(p2.part_number) from RAW.DIM_PART p2
            where p2.component_class_code = c.component_class_code
       )
    left join RAW.DIM_STOCK st
        on st.part_number = p.part_number
       and st.stock_id = (
            select min(s2.stock_id) from RAW.DIM_STOCK s2 where s2.part_number = p.part_number
       )
    where w.work_order_type = 'CORRECTIVE'
      and w.created_date between :window_start and :window_end;

    n_parts := sqlrowcount;

    -- =======================================================================
    -- GENEALOGY — close the failed serial, open the refurbished one
    -- =======================================================================
    -- close the outgoing serial
    update RAW.DIM_COMPONENT_GENEALOGY g
    set valid_to = f.repair_ts
    from GEN.GEN_FAILURE_EVENT f
    where g.component_id = f.component_id
      and g.serial_number = f.serial_number
      and g.valid_to is null
      and f.repair_ts <= :window_end;

    insert into RAW.DIM_COMPONENT_GENEALOGY (
        component_id, serial_number, valid_from, valid_to, event_type
    )
    select
        f.component_id,
        f.serial_number || 'R',
        f.repair_ts,
        null,
        'REPLACEMENT'
    from GEN.GEN_FAILURE_EVENT f
    where f.repair_ts <= :window_end
      and not exists (
          select 1 from RAW.DIM_COMPONENT_GENEALOGY g
          where g.component_id = f.component_id
            and g.serial_number = f.serial_number || 'R'
      );

    n_geneal := sqlrowcount;

    return 'FCT_WORK_ORDER: corrective=' || n_corrective || ' preventive=' || n_pm
        || ' inspection=' || n_insp || '; FCT_PART_MOVEMENT=' || n_parts
        || '; genealogy replacements=' || n_geneal;
end;
$$;
