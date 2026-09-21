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
--   * the Cortex Agent. It lives in SNOWFLAKE_INTELLIGENCE.AGENTS, outside our
--     database (04-code.md §2), so 70_agent must add an explicit drop here.
--   * compute pools, image repositories, notification integrations — all
--     account-level. None exist at foundation.
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

drop database if exists <% database %>;
