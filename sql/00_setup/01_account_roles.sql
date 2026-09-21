-- =============================================================================
-- 00_setup / 01 — account roles                        STAGE: ELEVATED, ONE-TIME
-- =============================================================================
-- Implements : US-44 (least-privilege roles)  ·  satisfies NFR-3  ·  tested by T-50
-- Authority  : docs/03-architecture/04-code.md §6
-- Run by     : just deploy-foundation   (never by hand — AGENTS.md > Deployment)
--
-- CREATE ROLE and GRANT ROLE are account-level operations, so this file is part
-- of the elevated stage described in docs/03-architecture/deployment.md §3.
-- ACCOUNTADMIN is used deliberately and only here: NFR-3 forbids ACCOUNTADMIN in
-- *application* code, and a one-time bootstrap is not application code. Nothing
-- the app or the agent ever executes runs from this file.
--
-- Idempotent: every statement is CREATE ... IF NOT EXISTS or a GRANT, both of
-- which are no-ops on a second run. Required by T-52 (succeeds twice in a row).
--
-- NOTE ON THE HIERARCHY — deliberate deviation from the §6 mermaid diagram.
-- The diagram draws WOA_APP --> {WOA_RMC, WOA_PLANNER, WOA_EXEC, WOA_TECH}, but
-- the grant table on the same page defines WOA_EXEC as "SELECT on SERVING only"
-- and WOA_TECH as "SELECT on the job-pack view only". Under Snowflake semantics
-- a role inherits the roles granted TO it, so no single arrow direction can
-- satisfy both the diagram and the table:
--   * grant the personas TO WOA_APP  -> WOA_APP gains the approval and
--     suppression procedures, breaking FR-35 / T-33;
--   * grant WOA_APP TO all personas  -> WOA_EXEC and WOA_TECH gain SELECT on
--     ML, CURATED and ENGINE, breaking their own "notably lacks" cells.
-- The table is the more specific statement, so it wins: WOA_APP is granted only
-- to the two roles the table defines as supersets of it. WOA_EXEC and WOA_TECH
-- are standalone and inherit nothing. Recorded in STATE.md §7.
-- =============================================================================

use role ACCOUNTADMIN;

-- --- the nine WOA_* roles ----------------------------------------------------
-- Comments are load-bearing: `show roles like 'WOA%'` is how the next person
-- discovers what each role is for.

create role if not exists WOA_ADMIN
    comment = 'Owns the WIND_OPS_AI database and its schemas; runs setup. No account-level privileges (NFR-3)';

create role if not exists WOA_APP
    comment = 'Streamlit app runtime. SELECT on SERVING/ENGINE/ML/CURATED. Writes to ACTION only via approval procedures (FR-35)';

create role if not exists WOA_AGENT
    comment = 'Cortex Agent. READ ONLY. No write privilege anywhere and nothing at all on ACTION (FR-53, T-47)';

create role if not exists WOA_SCHEDULER
    comment = 'Daily automation. Refreshes scores and suggestions; never applies. No privilege on ACTION (NFR-19, FR-85)';

create role if not exists WOA_ENGINEER
    comment = 'Developer role. CREATE inside a personal clone only; no grant on the shared WIND_OPS_AI';

create role if not exists WOA_RMC
    comment = 'P-7/P-2 remote monitoring. WOA_APP plus the suppression procedure. Cannot approve work orders';

create role if not exists WOA_PLANNER
    comment = 'P-3 planning. WOA_APP plus the work-order approval procedure';

create role if not exists WOA_EXEC
    comment = 'P-1/P-5 executive read. SELECT on SERVING only — no component detail, no engine internals';

create role if not exists WOA_TECH
    comment = 'P-4 technician. SELECT on the job-pack view only';

-- --- hierarchy ---------------------------------------------------------------
-- In Snowflake, `grant role A to role B` makes B inherit A. Read every line
-- below as "the role on the right gains the privileges of the role on the left".

-- Make the whole tree administrable from SYSADMIN, per the §6 diagram. This is
-- the standard pattern and the one part of the diagram that is unambiguous.
grant role WOA_ADMIN to role SYSADMIN;

-- WOA_ADMIN administers the four functional roles.
grant role WOA_APP to role WOA_ADMIN;
grant role WOA_AGENT to role WOA_ADMIN;
grant role WOA_SCHEDULER to role WOA_ADMIN;
grant role WOA_ENGINEER to role WOA_ADMIN;

-- The two persona roles the grant table defines as supersets of WOA_APP.
grant role WOA_PLANNER to role WOA_ADMIN;
grant role WOA_RMC to role WOA_ADMIN;
grant role WOA_APP to role WOA_PLANNER;
grant role WOA_APP to role WOA_RMC;

-- WOA_EXEC and WOA_TECH are deliberately NOT granted WOA_APP — see the note at
-- the top of this file. They are administrable from WOA_ADMIN and nothing else.
grant role WOA_EXEC to role WOA_ADMIN;
grant role WOA_TECH to role WOA_ADMIN;

-- --- what this file must never do -------------------------------------------
-- No GRANT ... TO ROLE PUBLIC   (reference-solution defect G-11)
-- No ALTER ACCOUNT              (04-code.md §6 absolute rule 3)
-- No ALTER USER ... SET DEFAULT_ROLE for WOA_SCHEDULER — Q-78 is still open and
--   is a human decision (STATE.md §4). The role exists; wiring an identity to it
--   does not happen here.
