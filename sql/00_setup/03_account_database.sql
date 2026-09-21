-- =============================================================================
-- 00_setup / 03 — database                             STAGE: ELEVATED, ONE-TIME
-- =============================================================================
-- Implements : US-44, US-45  ·  satisfies NFR-3, NFR-6  ·  tested by T-50, T-52
-- Authority  : docs/03-architecture/04-code.md §1, deployment.md §2, §4
--
-- Parameter  : <% database %>   e.g. WIND_OPS_AI_DEV_JP  (dev) or WIND_OPS_AI (shared)
--
-- NFR-6: the database name is ALWAYS a parameter, never a literal. `snow sql`
-- renders <% database %> client-side and errors outright if the variable is not
-- supplied, so an unset parameter fails loudly rather than producing an empty
-- identifier. Verified by execution on snow CLI 3.27.
--
-- WHY THIS IS THE ELEVATED STAGE, AND WHY OWNERSHIP MOVES.
-- 04-code.md §6 requires WOA_ADMIN to own the database and its schemas while
-- "notably lacking account-level privileges". CREATE DATABASE *is* an
-- account-level privilege, so the two cannot both hold if WOA_ADMIN creates it.
-- Resolution: ACCOUNTADMIN creates the database here, then hands ownership to
-- WOA_ADMIN. WOA_ADMIN ends up owning everything and never holds an
-- account-level grant. Recorded in STATE.md §7.
--
-- PROHIBITED, per deployment.md §4: CREATE OR REPLACE DATABASE. It would
-- silently destroy a same-named database, including a colleague's clone. We use
-- IF NOT EXISTS, which is also what makes this re-runnable for T-52.
-- =============================================================================

use role ACCOUNTADMIN;

create database if not exists <% database %>
    comment = 'Wind Ops AI — predictive maintenance and OEE command center. SYNTHETIC DATA ONLY (AGENTS.md rule 5)';

-- CREATE DATABASE always creates a PUBLIC schema. The plan specifies exactly ten
-- schemas, and an unowned schema that no script creates is precisely the kind of
-- object AGENTS.md > Deployment calls a defect.
--
-- It is dropped HERE, not in 10_schemas.sql, and the reason is easy to get wrong:
-- GRANT OWNERSHIP ON DATABASE transfers only the database object, NOT the schemas
-- inside it. PUBLIC is created owned by ACCOUNTADMIN, so ACCOUNTADMIN is the only
-- role that can drop it. Attempting this after the ownership transfer below fails
-- with insufficient privileges.
--
-- IF EXISTS keeps it idempotent on the second run, when it is already gone.
drop schema if exists <% database %>.PUBLIC;

-- Hand the database to WOA_ADMIN. COPY CURRENT GRANTS preserves anything already
-- granted on a re-run, so this does not claw back privileges granted by a later
-- numbered script.
--
-- The ten real schemas are created by 10_schemas.sql as WOA_ADMIN, so WOA_ADMIN
-- owns them by construction and no schema-level ownership transfer is needed.
grant ownership on database <% database %> to role WOA_ADMIN copy current grants;
