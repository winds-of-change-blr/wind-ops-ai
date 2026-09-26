-- =============================================================================
-- 80_app / 02 — create the app from staged source                STAGE: WOA_ADMIN
-- =============================================================================
-- Runs AFTER `just deploy-app` has copied streamlit_app.py and environment.yml
-- to APP.WOA_APP_STAGE. See 01_streamlit.sql for why the runtime is explicit.
-- Parameter  : <% database %>
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace streamlit APP.WOA_COMMAND_CENTER
    from '@<% database %>.APP.WOA_APP_STAGE'
    main_file = 'streamlit_app.py'
    query_warehouse = WOA_APP_WH
    runtime_name = 'SYSTEM$WAREHOUSE_RUNTIME'
    title = 'Wind Ops AI — Command Center'
    comment = 'Predictive maintenance and OEE command center. SYNTHETIC DATA ONLY (AGENTS.md rule 5).';

-- Not live until a version is promoted (or the owner opens it in Snowsight).
alter streamlit APP.WOA_COMMAND_CENTER add live version from last;
