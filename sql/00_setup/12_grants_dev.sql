-- =============================================================================
-- 00_setup / 12 — developer grants                  STAGE: WOA_ADMIN, env=dev ONLY
-- =============================================================================
-- Implements : US-44  ·  satisfies NFR-3  ·  tested by T-50
-- Authority  : docs/03-architecture/04-code.md §6 (WOA_ENGINEER row), deployment.md §2
--
-- Parameter  : <% database %>   — MUST be a personal clone, never WIND_OPS_AI
--
-- WHY THIS IS A SEPARATE FILE.
-- 04-code.md §6 gives WOA_ENGINEER "CREATE in a personal clone" and explicitly
-- "notably lacks: any grant on WIND_OPS_AI". That is a rule the *caller* has to
-- honour, because SQL cannot see which environment it was invoked for. Keeping
-- these grants in their own file lets `just deploy-foundation` run it only when
-- env=dev and skip it entirely for env=shared — a decision that is then visible
-- in the recipe rather than buried in a conditional inside a script.
--
-- If you are reading this because a developer cannot create an object in the
-- shared database: that is working as designed. Work in your own clone.
--
-- Idempotent: GRANT is a no-op when the privilege is already held (T-52).
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;

-- Database-level visibility.
grant usage on database <% database %> to role WOA_ENGINEER;

-- CREATE rights in the schemas a developer actually builds in. Granted schema by
-- schema rather than with a blanket database grant, so that adding a schema is a
-- deliberate decision here rather than an accident.
--
-- Deliberately NOT granted: CREATE on ACTION. Even in a personal clone, the
-- approval-and-audit surface is built by the numbered scripts, not by hand — a
-- developer who can hand-create an ACTION table can accidentally prove T-33
-- passes against an object the real deployment never creates.

grant usage, create table, create view, create dynamic table, create procedure, create function, create stage
    on schema GEN to role WOA_ENGINEER;

grant usage, create table, create view, create dynamic table, create procedure, create function, create stage
    on schema RAW to role WOA_ENGINEER;

grant usage, create table, create view, create dynamic table, create procedure, create function
    on schema CURATED to role WOA_ENGINEER;

grant usage, create table, create view, create dynamic table, create procedure, create function
    on schema SERVING to role WOA_ENGINEER;

grant usage, create table, create view, create dynamic table, create procedure, create function
    on schema ML to role WOA_ENGINEER;

grant usage, create table, create view, create dynamic table, create procedure, create function
    on schema ENGINE to role WOA_ENGINEER;

grant usage, create table, create view, create procedure, create function, create stage
    on schema DOCS to role WOA_ENGINEER;

grant usage, create table, create view, create dynamic table, create procedure, create function
    on schema OPS to role WOA_ENGINEER;

grant usage, create streamlit, create stage
    on schema APP to role WOA_ENGINEER;

-- Read access to everything the developer can create, so they can actually test
-- what they built.
grant select on all tables in database <% database %> to role WOA_ENGINEER;
grant select on future tables in database <% database %> to role WOA_ENGINEER;
grant select on all views in database <% database %> to role WOA_ENGINEER;
grant select on future views in database <% database %> to role WOA_ENGINEER;
grant select on all dynamic tables in database <% database %> to role WOA_ENGINEER;
grant select on future dynamic tables in database <% database %> to role WOA_ENGINEER;
