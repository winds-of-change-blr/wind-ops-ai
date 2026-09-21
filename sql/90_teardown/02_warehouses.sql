-- =============================================================================
-- 90_teardown / 02 — warehouses                              DESTRUCTIVE
-- =============================================================================
-- Implements : US-44  ·  proven by T-52
-- Authority  : docs/03-architecture/deployment.md §5
--
-- Reverses 00_setup/02_account_warehouses.sql.
--
-- ACCOUNT-LEVEL, AND THEREFORE SHARED. These two warehouses are not per-clone:
-- every developer's WIND_OPS_AI_DEV_<INITIALS> uses the same WOA_APP_WH and
-- WOA_BUILD_WH. Dropping them removes compute for every clone in the account, not
-- just yours.
--
-- That is a deliberate choice, not an oversight: T-52 requires teardown to remove
-- *everything* setup created, and a judge running teardown in their own account
-- must be left with no residue. The protection lives in the recipe rather than
-- here — `just teardown` refuses env=shared outright and requires the database
-- name to be typed by hand. If you are running this file directly, you have
-- bypassed both guards.
--
-- Dropping a warehouse cancels its running queries. Warehouses go before roles
-- because a role that owns a warehouse cannot be dropped cleanly.
--
-- Idempotent: IF EXISTS.
-- =============================================================================

use role ACCOUNTADMIN;

drop warehouse if exists WOA_APP_WH;
drop warehouse if exists WOA_BUILD_WH;
