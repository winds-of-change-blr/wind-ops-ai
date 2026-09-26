-- =============================================================================
-- 50_action / 03 — who may call which procedure                    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-35, FR-53, NFR-19, 04-code.md role table
-- Proves     : T-33 (no direct write), T-76 grant half (scheduler never applies)
-- Parameter  : <% database %>
--
-- The grants are the whole security model, so they are stated positively here
-- and asserted negatively by DQ-ACTION-NO-DIRECT-GRANT:
--
--   WOA_RMC      suppress, revoke                  (P-7 remote monitoring)
--   WOA_PLANNER  draft, approve, reject work order (P-3 planning)
--   WOA_APP      NOTHING on ACTION tables or procedures
--   WOA_AGENT    NOTHING on ACTION, not even schema USAGE (11_grants)
--   WOA_SCHEDULER NOTHING on ACTION                (it refreshes; never applies)
--
-- DEVIATION from 04-code.md's role table, which lists "USAGE on SP_APPROVE_*"
-- under WOA_APP. WOA_RMC and WOA_PLANNER both inherit WOA_APP, so granting the
-- approval procedures to WOA_APP would let RMC approve work orders — which the
-- same table says RMC must NOT do. The persona-specific rows win, as they did
-- in 01_account_roles.sql. Recorded in STATE.md §7.
--
-- No table grant appears in this file, and none may: ownership stays with
-- WOA_ADMIN and every write goes through a procedure.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;

grant usage on schema ACTION to role WOA_RMC;
grant usage on schema ACTION to role WOA_PLANNER;

grant usage on procedure ACTION.SP_APPROVE_SUPPRESSION(varchar, number, varchar, varchar, varchar) to role WOA_RMC;
grant usage on procedure ACTION.SP_REVOKE_SUPPRESSION(varchar, varchar, varchar, varchar)          to role WOA_RMC;

grant usage on procedure ACTION.SP_DRAFT_WORK_ORDER(varchar, varchar, varchar)                     to role WOA_PLANNER;
grant usage on procedure ACTION.SP_APPROVE_WORK_ORDER(varchar, varchar, varchar)                   to role WOA_PLANNER;
grant usage on procedure ACTION.SP_REJECT_WORK_ORDER_DRAFT(varchar, varchar, varchar, varchar, varchar) to role WOA_PLANNER;
