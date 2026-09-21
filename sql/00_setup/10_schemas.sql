-- =============================================================================
-- 00_setup / 10 — schemas                                    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-44  ·  satisfies NFR-3, NFR-6  ·  tested by T-52
-- Authority  : docs/03-architecture/04-code.md §2, 02-container.md §1, §3
--
-- Parameter  : <% database %>
--
-- First file of the non-elevated stage. From here on nothing runs as
-- ACCOUNTADMIN: WOA_ADMIN owns the database (03_account_database.sql) and so can
-- create schemas inside it without any account-level privilege.
--
-- Exactly ten schemas. The boundaries are deliberate, not cosmetic — each one
-- exists so that a grant can be made small enough to reason about:
--   * GEN must be droppable and must never be grantable to the app.
--   * ENGINE is separate from SERVING because the agent reads both and writes
--     to neither.
--   * ACTION is the ONLY schema writable at runtime, which keeps the single
--     write grant small, obvious and auditable (FR-35).
--   * OPS is separate because observability must survive the failure of the
--     thing it observes.
--
-- The agent is NOT here. Cortex Agents live in SNOWFLAKE_INTELLIGENCE.AGENTS, a
-- platform-mandated location (04-code.md §2). CMP-15 (roles, grants, secrets)
-- deliberately has no schema at all.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;

-- --- the ten schemas ---------------------------------------------------------

create schema if not exists GEN
    comment = 'CMP-1 synthetic data generator procedures. Droppable; never granted to the app';

create schema if not exists RAW
    comment = 'CMP-2 landing tables and the document stage. Written by the generator and simulated arrivals';

create schema if not exists CURATED
    comment = 'CMP-3 conformed dimensions and facts, as dynamic tables';

create schema if not exists SERVING
    comment = 'CMP-5 metric views and CMP-12 semantic view. One definition per metric (FR-27)';

create schema if not exists ML
    comment = 'CMP-4/CMP-6 features, model instances, scores and drivers. No score without drivers (FR-18)';

create schema if not exists ENGINE
    comment = 'CMP-7..9 alarm correlation, ranking, constraints. Pure computation — readable, never writable';

create schema if not exists ACTION
    comment = 'CMP-10 work orders, approvals, audit. The ONLY runtime-writable schema. App only, with approval (FR-35)';

create schema if not exists DOCS
    comment = 'CMP-11 parsed documents, chunks and the Cortex Search service';

create schema if not exists OPS
    comment = 'CMP-16 freshness, data quality, model runs, cost. Separate so it survives what it observes';

create schema if not exists APP
    comment = 'CMP-14 the Streamlit in Snowflake object (ADR-0020)';

-- --- a note on the schema you will not find here -----------------------------
-- CREATE DATABASE also creates a PUBLIC schema, which the plan does not ask for.
-- It is dropped in 03_account_database.sql rather than here, because PUBLIC is
-- owned by ACCOUNTADMIN and GRANT OWNERSHIP ON DATABASE does not transfer the
-- schemas inside the database — so WOA_ADMIN cannot drop it.
--
-- After this file runs, `show schemas in database <% database %>` should list the
-- ten above plus INFORMATION_SCHEMA, and nothing else.
