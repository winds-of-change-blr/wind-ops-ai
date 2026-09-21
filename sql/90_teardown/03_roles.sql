-- =============================================================================
-- 90_teardown / 03 — roles                                   DESTRUCTIVE
-- =============================================================================
-- Implements : US-44  ·  proven by T-52
-- Authority  : docs/03-architecture/deployment.md §5
--
-- Reverses 00_setup/01_account_roles.sql. Last, because everything else was
-- owned by or granted to these roles.
--
-- ACCOUNT-LEVEL, AND THEREFORE SHARED — the same warning as 02_warehouses.sql
-- applies, more sharply. Dropping WOA_ADMIN removes the role that owns every
-- other developer's clone. The guards are in `just teardown`, not here.
--
-- DROP ROLE revokes the role from every user and role it was granted to, so the
-- hierarchy built in 00_setup/01 needs no separate unwinding. Child-before-parent
-- order below is cosmetic rather than required, but it reads as the exact reverse
-- of setup, which is the property T-52 cares about.
--
-- Idempotent: IF EXISTS.
--
-- If a DROP ROLE here fails with "role has dependent objects", something outside
-- this repository created an object owned by a WOA_* role. That is the defect
-- AGENTS.md > Deployment describes: record it in STATE.md §7 and fold whatever
-- created it into a recipe.
-- =============================================================================

use role ACCOUNTADMIN;

-- Persona roles first — the leaves of the hierarchy.
drop role if exists WOA_TECH;
drop role if exists WOA_EXEC;
drop role if exists WOA_RMC;
drop role if exists WOA_PLANNER;

-- Then the four functional roles.
drop role if exists WOA_ENGINEER;
drop role if exists WOA_SCHEDULER;
drop role if exists WOA_AGENT;
drop role if exists WOA_APP;

-- WOA_ADMIN last: it owned the database and the schemas.
drop role if exists WOA_ADMIN;
