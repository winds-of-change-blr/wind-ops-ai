-- =============================================================================
-- 15_quality / 09 — automation assertions: the digest task          STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : T-76 (GATING: refreshes, never applies), T-77 (the digest exists)
-- Authority  : ADR-0019, sql/85_ops/01_daily_digest.sql
-- Parameter  : <% database %>
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-T76-TASK-OWNED-BY-SCHEDULER', 'T-76', 'G4', 'The daily digest task exists, is scheduled, started, and owned by WOA_SCHEDULER',
            'An automation running with a human''s or an admin''s privileges', true),
        ('DQ-T76-TASK-SUCCEEDED',          'T-76', 'G4', 'The digest task has at least one SUCCEEDED run in the last 7 days',
            'A schedule that exists on paper and has never run', true),
        ('DQ-T76-SCHEDULER-ONE-WRITE',     'T-76', 'G4', 'WOA_SCHEDULER''s only write privilege is INSERT on OPS.OPS_DIGEST',
            'An automation that can change what it reports on', true),
        ('DQ-T77-DIGEST-FRESH',            'T-77', 'G4', 'A digest row built by WOA_SCHEDULER in the last 26 hours, with risks and noise populated',
            'A shift starting without the digest it was promised', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_OPS_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id  varchar;
    n       integer;
    detail  varchar;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    show tasks like 'T_DAILY_DIGEST' in schema OPS;
    select count(*), max("owner" || ' / ' || "state" || ' / ' || "schedule")
      into :n, :detail
      from table(result_scan(last_query_id()))
     where "owner" = 'WOA_SCHEDULER' and "state" = 'started' and "schedule" is not null;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T76-TASK-OWNED-BY-SCHEDULER', 'T-76', current_timestamp()::timestamp_ntz,
           :n = 1, :n, 1, coalesce(:detail, 'task missing, suspended, unscheduled or not owned by WOA_SCHEDULER');

    select count(*) into :n
      from table(information_schema.task_history(
               task_name => 'T_DAILY_DIGEST',
               scheduled_time_range_start => dateadd('day', -7, current_timestamp()),
               result_limit => 1000))
     where database_name = current_database() and schema_name = 'OPS' and state = 'SUCCEEDED';
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T76-TASK-SUCCEEDED', 'T-76', current_timestamp()::timestamp_ntz,
           :n >= 1, :n, 1, :n || ' SUCCEEDED runs of OPS.T_DAILY_DIGEST in 7 days';

    show grants to role WOA_SCHEDULER;
    select count(*), listagg("privilege" || ' ON ' || "name", '; ')
      into :n, :detail
      from table(result_scan(last_query_id()))
     where "privilege" in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'CREATE TABLE', 'CREATE VIEW', 'CREATE PROCEDURE')
       and not ("privilege" = 'INSERT' and "name" ilike '%.OPS.OPS_DIGEST');
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T76-SCHEDULER-ONE-WRITE', 'T-76', current_timestamp()::timestamp_ntz,
           :n = 0, :n, 0, coalesce(nullif(:detail, ''), 'only INSERT on OPS.OPS_DIGEST');

    select count(*) into :n
      from OPS.OPS_DIGEST
     where built_by_role = 'WOA_SCHEDULER'
       and built_at >= dateadd('hour', -26, current_timestamp()::timestamp_ntz)
       and array_size(top_risks) > 0 and alarm_noise:incidents::integer > 0;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T77-DIGEST-FRESH', 'T-77', current_timestamp()::timestamp_ntz,
           :n >= 1, :n, 1, :n || ' populated digests by WOA_SCHEDULER in 26h';

    return 'Ops quality run ' || :run_id || ' complete';
end;
$$;
