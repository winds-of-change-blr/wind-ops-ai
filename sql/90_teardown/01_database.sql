-- =============================================================================
-- 90_teardown / 01 — database                                DESTRUCTIVE
-- =============================================================================
-- Implements : US-44  ·  proven by T-52 ("teardown removes everything")
-- Authority  : docs/03-architecture/deployment.md §5
--
-- Parameter  : <% database %>
--
-- Reverses 00_setup/03_account_database.sql and everything built inside it.
--
-- WHY THIS IS ONE STATEMENT AND NOT TWELVE.
-- deployment.md §5 gives the teardown order as: app -> agent -> search service ->
-- ML instances -> dynamic tables -> views -> procedures -> tables -> schemas ->
-- database -> warehouses -> roles. Everything from "app" through "schemas" lives
-- *inside* the database, and DROP DATABASE removes all of it in dependency order
-- for us. Enumerating them would be a list that silently goes stale every time a
-- later script adds an object.
--
-- WHAT DROP DATABASE DOES **NOT** REACH — and must be added here as it is built:
--   * the Snowflake Intelligence object (00_setup/04). It is account-level
--     and may list other teams' agents, so our agent is removed from it and
--     the object is dropped ONLY if nothing else is left in it. The agent
--     itself lives in <% database %>.GEN and goes with the database.
--   * compute pools, image repositories, notification integrations — all
--     account-level. None exist.
-- Until those exist, this file is deliberately short. See ../90_teardown/README.md.
--
-- Idempotent: IF EXISTS, so running teardown twice is not an error. T-52 needs a
-- clean database afterwards, and "already gone" is clean.
--
-- NOTE: this is a DROP, not a DROP ... CASCADE — Snowflake has no CASCADE on
-- DROP DATABASE; the containment drop is implicit. The database goes to Time
-- Travel rather than vanishing, so a mistaken teardown is recoverable with
-- UNDROP DATABASE within the retention window.
-- =============================================================================

use role ACCOUNTADMIN;

execute immediate $$
begin
    show snowflake intelligences like 'SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT';
    if ((select count(*) from table(result_scan(last_query_id()))) = 0) then
        return 'no Snowflake Intelligence object';
    end if;
    show agents in snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
    let rs resultset := (select count_if("database_name" = '<% database %>') as ours,
                                count_if("database_name" <> '<% database %>') as others
                         from table(result_scan(last_query_id())));
    let cur cursor for rs;
    let ours integer := 0;
    let others integer := 0;
    for rw in cur do
        ours := rw.ours;
        others := rw.others;
    end for;
    if (ours > 0) then
        alter snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
            drop agent <% database %>.GEN.WOA_OPS_AGENT;
    end if;
    if (others = 0) then
        drop snowflake intelligence if exists SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
        return 'Snowflake Intelligence object dropped';
    end if;
    return 'agent removed; object kept for ' || others || ' other agent(s)';
end;
$$;

drop database if exists <% database %>;
