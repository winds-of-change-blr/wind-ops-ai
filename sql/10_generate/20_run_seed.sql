-- =============================================================================
-- 10_generate / 20 — run the generator                         STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the body of `just seed` (US-8..US-12, T-8 determinism)
-- Parameters : <% database %>, <% history_days %>, <% seed %>,
--              <% damage_multiplier %>, <% accel_share %>, <% interval_min %>
--
-- Every parameter is supplied by the recipe, never hardcoded here (NFR-6). The
-- defaults live in the justfile with the reasoning for each value.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

call GEN.SP_GENERATE_ALL(
    <% history_days %>,
    '<% seed %>',
    <% damage_multiplier %>,
    <% accel_share %>,
    <% interval_min %>
);
