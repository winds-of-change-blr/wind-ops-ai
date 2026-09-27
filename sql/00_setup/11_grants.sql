-- =============================================================================
-- 00_setup / 11 — grants                                     STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-44  ·  satisfies NFR-3  ·  tested by T-50, T-52
--              Underpins FR-35/T-33 (no write without approval) and
--              FR-53/T-47 (no destructive tool reachable from the agent).
-- Authority  : docs/03-architecture/04-code.md §6, 02-container.md §4
--
-- Parameter  : <% database %>
--
-- THE POINT OF THIS FILE. WOA_AGENT holds no write privilege anywhere and no
-- privilege at all on ACTION. That is enforced here, by the absence of a grant —
-- not by a prompt instruction. A prompt can be argued with; a missing grant
-- cannot. Every "deliberately absent" comment below is load-bearing: it is the
-- reason a test can assert the negative.
--
-- FUTURE GRANTS, AND WHY. At foundation time the schemas are empty — no tables,
-- no views. Granting SELECT only on what exists today would silently fail to
-- cover everything 10_generate onward creates, and someone would "fix" it later
-- with a broad grant. Instead each read role gets FUTURE grants now, so the
-- privilege set is declared once, here, where it can be reviewed. The matching
-- ON ALL grants make re-runs converge if an object was created before its grant.
--
-- Idempotent: GRANT is a no-op when the privilege is already held (T-52).
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;

-- =============================================================================
-- 1. Database usage
-- =============================================================================
-- USAGE on the database is the floor for any read. It conveys no data access on
-- its own. Granted to every role that touches the database; NOT to PUBLIC.

grant usage on database <% database %> to role WOA_APP;
grant usage on database <% database %> to role WOA_AGENT;
grant usage on database <% database %> to role WOA_SCHEDULER;
grant usage on database <% database %> to role WOA_EXEC;
grant usage on database <% database %> to role WOA_TECH;

-- WOA_PLANNER and WOA_RMC inherit WOA_APP, so they need nothing of their own.
-- WOA_ADMIN owns the database and needs no grant on it.
-- WOA_ENGINEER gets nothing: per 04-code.md §6 it has no grant on WIND_OPS_AI,
-- and the personal clones it used to build in were retired on 2026-09-27.

-- =============================================================================
-- 2. WOA_APP — the application runtime
-- =============================================================================
-- SELECT on SERVING, ENGINE, ML, CURATED. Notably LACKS direct DML on ACTION:
-- writes go through the approval procedures only (FR-35, T-33).

grant usage on schema SERVING to role WOA_APP;
grant usage on schema ENGINE to role WOA_APP;
grant usage on schema ML to role WOA_APP;
grant usage on schema CURATED to role WOA_APP;

grant select on all tables in schema SERVING to role WOA_APP;
grant select on future tables in schema SERVING to role WOA_APP;
grant select on all views in schema SERVING to role WOA_APP;
grant select on future views in schema SERVING to role WOA_APP;

grant select on all tables in schema ENGINE to role WOA_APP;
grant select on future tables in schema ENGINE to role WOA_APP;
grant select on all views in schema ENGINE to role WOA_APP;
grant select on future views in schema ENGINE to role WOA_APP;

grant select on all tables in schema ML to role WOA_APP;
grant select on future tables in schema ML to role WOA_APP;
grant select on all views in schema ML to role WOA_APP;
grant select on future views in schema ML to role WOA_APP;

grant select on all tables in schema CURATED to role WOA_APP;
grant select on future tables in schema CURATED to role WOA_APP;
grant select on all views in schema CURATED to role WOA_APP;
grant select on future views in schema CURATED to role WOA_APP;

-- CURATED is built from dynamic tables (CMP-3). Dynamic tables are a distinct
-- object type for grant purposes, so SELECT ON TABLES does not reach them.
grant select on all dynamic tables in schema CURATED to role WOA_APP;
grant select on future dynamic tables in schema CURATED to role WOA_APP;

-- WOA_APP needs to SEE the ACTION schema so the app can call the approval
-- procedures that live there. USAGE on a schema conveys no access to its
-- contents — the procedure grants themselves are made in 50_action, and the
-- tables are never granted to WOA_APP at all.
grant usage on schema ACTION to role WOA_APP;

-- Deliberately absent for WOA_APP:
--   * any privilege on ACTION tables — no SELECT, no INSERT, no UPDATE, no DELETE
--   * any privilege on GEN — the generator is not application surface
--   * any privilege on RAW — the app reads curated data, never landing tables
--   * any privilege on OPS — observability is not the app's business

-- =============================================================================
-- 3. WOA_AGENT — read only, and provably so
-- =============================================================================
-- SELECT on SERVING and ENGINE. Nothing else. This role is the reason T-47 can
-- assert that no destructive tool is reachable from any agent path.

grant usage on schema SERVING to role WOA_AGENT;
grant usage on schema ENGINE to role WOA_AGENT;

grant select on all tables in schema SERVING to role WOA_AGENT;
grant select on future tables in schema SERVING to role WOA_AGENT;
grant select on all views in schema SERVING to role WOA_AGENT;
grant select on future views in schema SERVING to role WOA_AGENT;

grant select on all tables in schema ENGINE to role WOA_AGENT;
grant select on future tables in schema ENGINE to role WOA_AGENT;
grant select on all views in schema ENGINE to role WOA_AGENT;
grant select on future views in schema ENGINE to role WOA_AGENT;

-- Deliberately absent for WOA_AGENT — each line is asserted by a test:
--   * EVERYTHING on ACTION, including USAGE on the schema (T-33, T-47).
--     WOA_APP gets USAGE on ACTION; WOA_AGENT does not, so the agent cannot even
--     resolve the name of an approval procedure.
--   * any INSERT, UPDATE, DELETE, MERGE or TRUNCATE anywhere (T-47)
--   * any privilege on ML — the agent explains scores through SERVING/ENGINE
--     views, never by reading model internals
--   * any privilege on GEN, RAW or OPS
--   * USAGE on the Cortex Search service and the semantic view — those objects do
--     not exist yet and are granted in 60_docs and 30_serve respectively

-- =============================================================================
-- 4. WOA_SCHEDULER — the nightly automation
-- =============================================================================
-- It refreshes; it never applies (FR-85, T-76). SELECT on CURATED, ML, SERVING,
-- ENGINE. The INSERT grants on the score, suggestion and digest tables are
-- deliberately NOT here: those tables do not exist yet, and a blanket
-- "INSERT on future tables in ML" would hand the automation write access to
-- tables nobody has designed. They are granted table-by-table by the scripts
-- that create them (python/ml, 40_engine, and OPS).

grant usage on schema CURATED to role WOA_SCHEDULER;
grant usage on schema ML to role WOA_SCHEDULER;
grant usage on schema SERVING to role WOA_SCHEDULER;
grant usage on schema ENGINE to role WOA_SCHEDULER;
grant usage on schema OPS to role WOA_SCHEDULER;

grant select on all tables in schema CURATED to role WOA_SCHEDULER;
grant select on future tables in schema CURATED to role WOA_SCHEDULER;
grant select on all views in schema CURATED to role WOA_SCHEDULER;
grant select on future views in schema CURATED to role WOA_SCHEDULER;
grant select on all dynamic tables in schema CURATED to role WOA_SCHEDULER;
grant select on future dynamic tables in schema CURATED to role WOA_SCHEDULER;

grant select on all tables in schema ML to role WOA_SCHEDULER;
grant select on future tables in schema ML to role WOA_SCHEDULER;
grant select on all views in schema ML to role WOA_SCHEDULER;
grant select on future views in schema ML to role WOA_SCHEDULER;

grant select on all tables in schema SERVING to role WOA_SCHEDULER;
grant select on future tables in schema SERVING to role WOA_SCHEDULER;
grant select on all views in schema SERVING to role WOA_SCHEDULER;
grant select on future views in schema SERVING to role WOA_SCHEDULER;

grant select on all tables in schema ENGINE to role WOA_SCHEDULER;
grant select on future tables in schema ENGINE to role WOA_SCHEDULER;
grant select on all views in schema ENGINE to role WOA_SCHEDULER;
grant select on future views in schema ENGINE to role WOA_SCHEDULER;

-- Deliberately absent for WOA_SCHEDULER:
--   * EVERYTHING on ACTION, including schema USAGE. It refreshes; it never
--     applies (T-76).
--   * blanket INSERT anywhere — see the note above.

-- =============================================================================
-- 5. WOA_EXEC — executive read
-- =============================================================================
-- SELECT on SERVING only. Notably lacks component-level detail and engine
-- internals, which is why it is NOT granted WOA_APP (see 01_account_roles.sql).

grant usage on schema SERVING to role WOA_EXEC;

grant select on all tables in schema SERVING to role WOA_EXEC;
grant select on future tables in schema SERVING to role WOA_EXEC;
grant select on all views in schema SERVING to role WOA_EXEC;
grant select on future views in schema SERVING to role WOA_EXEC;

-- Deliberately absent: ENGINE, ML, CURATED, RAW, GEN, ACTION, OPS, DOCS.

-- =============================================================================
-- 6. WOA_TECH — the technician
-- =============================================================================
-- SELECT on the job-pack view ONLY. That view (SERVING) does not exist yet, so
-- this file grants schema visibility and stops. There is deliberately no FUTURE
-- grant here: a future grant would give WOA_TECH every view in SERVING as it is
-- created, which is exactly the "everything else" its grant table row excludes.
-- The single view grant is made in 30_serve, next to the view it names.

grant usage on schema SERVING to role WOA_TECH;

-- =============================================================================
-- 7. Nobody gets GEN, and nobody gets PUBLIC
-- =============================================================================
-- GEN holds the synthetic data generator. 02-container.md §3 requires that it be
-- droppable and never grantable to the app, so it is granted to no role at all;
-- WOA_ADMIN reaches it by ownership. Stated here as an explicit non-action so a
-- reader does not conclude it was forgotten.
--
-- RAW, DOCS and OPS are likewise granted to no runtime role in this file. DOCS is
-- reached by the agent through the Cortex Search service (60_docs), not by
-- reading its tables; OPS is read by WOA_ADMIN and written by the pipelines.
--
-- No GRANT ... TO ROLE PUBLIC appears anywhere in this repository. That was
-- reference-solution defect G-11 and deployment.md §4 prohibits it outright.
