-- =============================================================================
-- 80_app / 01 — the command center app, WAREHOUSE runtime        STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : M8 (ADR-0020, amended by I-17)
-- Parameter  : <% database %>
--
-- RUNTIME_NAME IS SET EXPLICITLY, never left to a default. Snowflake is moving
-- new Streamlit apps to default to the CONTAINER runtime (BCR 2026_06), and the
-- container runtime installs every package from pypi.org at boot. On a trial
-- account that is impossible: "External access is not supported for trial
-- accounts". Verified three ways on 2026-09-26 before this file existed. The
-- warehouse runtime resolves environment.yml from Snowflake's own Anaconda
-- channel instead, so it needs no egress at all.
--
-- CREATE OR REPLACE is acceptable here and only here: a Streamlit object holds
-- no data, only a copy of staged source. 04-code.md §8's rule is about data.
--
-- Under SiS the app runs as the VIEWER's role, so least privilege (NFR-3) is a
-- property of the deployment — the argument ADR-0020 rests on.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create stage if not exists APP.WOA_APP_STAGE
    directory = (enable = true)
    comment = 'Source for WOA_COMMAND_CENTER. SYNTHETIC DATA ONLY.';
