-- =============================================================================
-- 00_setup / 02 — warehouses                           STAGE: ELEVATED, ONE-TIME
-- =============================================================================
-- Implements : US-44  ·  satisfies NFR-3, NFR-8 (cost)  ·  tested by T-50, T-52
-- Authority  : docs/03-architecture/04-code.md §5, deployment.md §6
--
-- Two warehouses, deliberately. Every standing warehouse is a cost risk against a
-- $400 trial ceiling, and the biggest risk is not a heavy query — it is an idle
-- warehouse left running overnight. Hence AUTO_SUSPEND = 60 on both.
--
-- CREATE WAREHOUSE is account-level, so this belongs to the elevated stage.
-- Idempotent via CREATE WAREHOUSE IF NOT EXISTS: on a second run the existing
-- warehouse is left exactly as it is, which is what T-52 requires. We do NOT use
-- CREATE OR ALTER here — that would silently resize a warehouse someone had
-- deliberately scaled up for a training run.
-- =============================================================================

use role ACCOUNTADMIN;

-- --- WOA_APP_WH — interactive -----------------------------------------------
-- App queries, agent queries, anything a human is waiting on.
create warehouse if not exists WOA_APP_WH
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'App, agent and interactive queries. XSMALL by policy (04-code.md §5)';

-- --- WOA_BUILD_WH — batch ----------------------------------------------------
-- Generation, pipeline refresh, model training. Resizable, but any script that
-- sizes it up must size it back down in the same script (04-code.md §5).
create warehouse if not exists WOA_BUILD_WH
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'Generation, pipeline refresh, model training. Resize up only inside a run, and back down in the same script';

-- --- usage grants ------------------------------------------------------------
-- USAGE only, never OPERATE: AUTO_RESUME means no role needs to start a
-- warehouse explicitly, so OPERATE would be privilege we cannot justify.
-- Never granted to PUBLIC — that was reference-solution defect G-11.

-- Interactive warehouse: everything a human or the agent drives.
grant usage on warehouse WOA_APP_WH to role WOA_APP;
grant usage on warehouse WOA_APP_WH to role WOA_AGENT;
grant usage on warehouse WOA_APP_WH to role WOA_EXEC;
grant usage on warehouse WOA_APP_WH to role WOA_TECH;

-- WOA_PLANNER and WOA_RMC inherit WOA_APP (01_account_roles.sql), so they pick
-- up WOA_APP_WH through inheritance and need no grant of their own.

-- Batch warehouse: setup, the nightly automation, and developer work.
grant usage on warehouse WOA_BUILD_WH to role WOA_ADMIN;
grant usage on warehouse WOA_BUILD_WH to role WOA_SCHEDULER;
grant usage on warehouse WOA_BUILD_WH to role WOA_ENGINEER;

-- WOA_ADMIN also needs the interactive warehouse to run verification queries
-- against what it just built.
grant usage on warehouse WOA_APP_WH to role WOA_ADMIN;

-- Deliberately absent:
--   * WOA_SCHEDULER on WOA_APP_WH  — the automation is batch; it must not
--     compete with a human for the interactive warehouse.
--   * any grant to PUBLIC.
--   * MONITOR on either warehouse — cost reporting runs as WOA_ADMIN.
