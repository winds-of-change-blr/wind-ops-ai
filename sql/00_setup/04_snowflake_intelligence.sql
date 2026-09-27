-- =============================================================================
-- 00_setup / 04 — Snowflake Intelligence                     ACCOUNT-LEVEL
-- =============================================================================
-- Implements : FR-86 (Snowflake Intelligence is one of the four demo surfaces)
-- Proves     : T-84 (with DQ-AGENT-REACHABLE in 15_quality/05)
-- Authority  : docs/03-architecture/02-container.md (AGENT usable from
--              Snowflake Intelligence as well as from the app)
--
-- The Snowflake Intelligence object is a single, account-level list of the
-- agents users see at ai.snowflake.com. One may already exist (Snowsight
-- creates it the first time its settings are opened), so this is IF NOT
-- EXISTS: it never replaces a list somebody else curated.
--
-- WOA_ADMIN gets MODIFY so 70_agent/02 can add the agent without ACCOUNTADMIN.
-- WOA_APP gets USAGE so RMC and planning users can open the list; the agent
-- itself still needs its own USAGE grant (70_agent/02), and every tool call
-- runs with the signed-in user's own grants.
--
-- Idempotent. Reversed by 90_teardown/01_database.sql.
-- =============================================================================

use role ACCOUNTADMIN;

create snowflake intelligence if not exists SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

grant modify on snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT to role WOA_ADMIN;
grant usage  on snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT to role WOA_ADMIN;
grant usage  on snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT to role WOA_APP;
