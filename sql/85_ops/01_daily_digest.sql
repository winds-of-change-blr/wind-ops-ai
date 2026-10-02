-- =============================================================================
-- 85_ops / 01 — the daily risk & alarm digest, run by WOA_SCHEDULER   STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : T-76 (the automation refreshes, never applies), T-77 (a digest a
--              human reads before their shift), FR-85, NFR-19
-- Authority  : ADR-0019, docs/06-coco/coco-usage-plan.md §4 row 4
-- Parameter  : <% database %>
--
-- Q-78 resolved: the automation runs as WOA_SCHEDULER, a role with no human
-- user. The task is OWNED by that role, so it runs with exactly its grants:
-- SELECT on ENGINE, INSERT on OPS.OPS_DIGEST and nothing on ACTION. A digest
-- can tell the planner what to approve; it can never approve.
--
-- Idempotent: re-running this file replaces the procedure and keeps the table,
-- its history and the task's run history (ALTER over CREATE OR REPLACE).
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create table if not exists OPS.OPS_DIGEST (
    digest_id        varchar        not null,
    built_at         timestamp_ntz  not null,
    built_by_role    varchar        not null,
    headline         varchar        not null,
    top_risks        array,
    alarm_noise      object,
    top_suggestions  array,
    is_synthetic     boolean        default true
)
comment = 'One row per daily digest (T-77). Written only by OPS.T_DAILY_DIGEST as WOA_SCHEDULER.';

create or replace procedure OPS.SP_BUILD_DIGEST()
returns varchar
language sql
comment = 'Builds one digest row from ENGINE. Read-only on everything except OPS.OPS_DIGEST (T-76).'
execute as caller
as
$$
declare
    did       varchar;
    risks     array;
    noise     object;
    sugg      array;
    n_high    integer;
    n_safety  integer;
    headline  varchar;
begin
    did := 'DIG-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    select array_agg(object_construct(
               'turbine_id', turbine_id, 'component', component_class_name,
               'risk_band', risk_band, 'risk_probability', round(risk_probability, 3),
               'expected_loss_inr', round(expected_loss_inr), 'top_drivers', top_drivers))
             within group (order by expected_loss_inr desc)
      into :risks
      from (select * from ENGINE.ENG_ALERT_RANKED order by expected_loss_inr desc limit 5);

    select count_if(risk_band = 'HIGH') into :n_high from ENGINE.ENG_ALERT_RANKED;

    select object_construct(
               'alarms', sum(n_alarms),
               'incidents', count(*),
               'compression_ratio', round(sum(n_alarms) / nullif(count(*), 0), 1),
               'nuisance', count_if(incident_class = 'NUISANCE'),
               'undetermined', count_if(incident_class = 'UNDETERMINED'),
               'safety_critical', count_if(is_safety_critical),
               -- Never report compression without the real failures beside it.
               'corroborated_real', count_if(is_corroborated or is_elevated)),
           count_if(is_safety_critical)
      into :noise, :n_safety
      from ENGINE.ENG_INCIDENT;

    select array_agg(object_construct(
               'suggestion_id', suggestion_id, 'site', site_code, 'start_day', start_day,
               'components', component_count, 'mobilisations_saved', mobilisations_saved,
               'expected_loss_covered_inr', round(expected_loss_covered_inr),
               'binding_constraint', binding_constraint))
             within group (order by expected_loss_covered_inr desc)
      into :sugg
      from (select * from ENGINE.ENG_SUGGESTION order by expected_loss_covered_inr desc limit 3);

    headline := :n_high || ' HIGH-risk components; ' || :n_safety
             || ' safety-critical incidents; ' || array_size(:sugg)
             || ' maintenance windows proposed for approval. Nothing has been applied.';

    insert into OPS.OPS_DIGEST (digest_id, built_at, built_by_role, headline,
                                top_risks, alarm_noise, top_suggestions)
    select :did, current_timestamp()::timestamp_ntz, current_role(), :headline,
           :risks, :noise, :sugg;

    return :did || ': ' || :headline;
end;
$$;

-- --- the scheduler's grants: read ENGINE (11_grants), write ONE table --------
grant usage on procedure OPS.SP_BUILD_DIGEST() to role WOA_SCHEDULER;
grant select, insert on table OPS.OPS_DIGEST to role WOA_SCHEDULER;
grant select on table OPS.OPS_DIGEST to role WOA_PLANNER;
grant select on table OPS.OPS_DIGEST to role WOA_RMC;
grant select on table OPS.OPS_DIGEST to role WOA_APP;

-- EXECUTE TASK is account-level and needs ACCOUNTADMIN (04-code.md §6 allows
-- account-level GRANTs in setup; it forbids ALTER ACCOUNT).
use role ACCOUNTADMIN;
grant execute task on account to role WOA_SCHEDULER;
use role WOA_ADMIN;

-- --- the task ----------------------------------------------------------------
-- 05:30 IST: before the 06:00 RMC shift handover the digest is written for.
create task if not exists OPS.T_DAILY_DIGEST
    warehouse = WOA_BUILD_WH
    schedule = 'USING CRON 30 5 * * * Asia/Kolkata'
    user_task_timeout_ms = 300000
    suspend_task_after_num_failures = 3
    comment = 'T-76/T-77: daily risk and alarm digest. Runs as WOA_SCHEDULER; refreshes, never applies.'
as
    call OPS.SP_BUILD_DIGEST();

-- Ownership decides the run-as role. COPY CURRENT GRANTS keeps OPERATE/MONITOR.
grant ownership on task OPS.T_DAILY_DIGEST to role WOA_SCHEDULER copy current grants;
grant monitor on task OPS.T_DAILY_DIGEST to role WOA_ADMIN;

use role WOA_SCHEDULER;
alter task OPS.T_DAILY_DIGEST resume;
-- Prove it now rather than waiting for 05:30: one run, as the owner.
execute task OPS.T_DAILY_DIGEST;
