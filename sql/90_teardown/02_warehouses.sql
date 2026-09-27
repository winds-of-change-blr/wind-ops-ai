-- =============================================================================
-- 90_teardown / 02 — warehouses                              DESTRUCTIVE
-- =============================================================================
-- Implements : US-44  ·  proven by T-52
-- Authority  : docs/03-architecture/deployment.md §5
--
-- Reverses 00_setup/02_account_warehouses.sql.
--
-- ACCOUNT-LEVEL. Dropping WOA_APP_WH and WOA_BUILD_WH removes compute for the
-- team database and the demo, for everyone.
--
-- That is a deliberate choice, not an oversight: T-52 requires teardown to remove
-- *everything* setup created, and a judge running teardown in their own account
-- must be left with no residue. The protection lives in the recipe rather than
-- here — `just teardown` requires the database name AND the account
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
