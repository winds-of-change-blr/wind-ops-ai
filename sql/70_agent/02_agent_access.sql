-- =============================================================================
-- 70_agent / 02 — who may use the agent, and where it appears
-- =============================================================================
-- Implements : FR-86, FR-48 (the agent is reachable by the people it is for)
-- Proves     : T-84 (DQ-AGENT-REACHABLE in 15_quality/05)
-- Parameter  : <% database %>
--
-- Snowflake Intelligence runs every tool call AS THE SIGNED-IN USER. So a user
-- needs USAGE on the agent AND on everything its two tools read. All of it is
-- granted to WOA_AGENT, the read-only role (04-code.md §6); 01_account_roles
-- grants WOA_AGENT to WOA_APP, so WOA_RMC and WOA_PLANNER inherit it.
--
-- Nothing here touches ACTION, and nothing is a write: T-33, T-47 and
-- DQ-T76-NO-ACTION-PRIV still hold. The one widening is two RAW dimensions:
-- the semantic view joins RAW.DIM_SITE and RAW.DIM_TURBINE (names, capacity,
-- site), and Analyst cannot answer a fleet question without them. Granted
-- table by table, never schema-wide.
--
-- Runs after 01_agent (the agent must exist) and 00_setup/04 (the Snowflake
-- Intelligence object must exist). Idempotent.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- The agent object and its schema.
grant usage on schema GEN to role WOA_AGENT;
grant usage on agent GEN.WOA_OPS_AGENT to role WOA_AGENT;

-- fleet_data -> Cortex Analyst over the semantic view (SERVING and ENGINE
-- SELECT already come from 00_setup/11_grants).
grant select on semantic view SERVING.SV_WIND_OPS to role WOA_AGENT;
grant usage on schema RAW to role WOA_AGENT;
grant select on table RAW.DIM_SITE to role WOA_AGENT;
grant select on table RAW.DIM_TURBINE to role WOA_AGENT;

-- maintenance_docs -> Cortex Search; READ on the stage opens a cited PDF.
grant usage on schema DOCS to role WOA_AGENT;
grant usage on cortex search service DOCS.CSS_MAINTENANCE_DOCS to role WOA_AGENT;
grant read on stage DOCS.MAINTENANCE_DOCS to role WOA_AGENT;

-- List it in Snowflake Intelligence. ADD AGENT errors if it is already
-- listed (400203), so add only when missing.
execute immediate $$
begin
    show agents in snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
    let n integer := (select count(*) from table(result_scan(last_query_id()))
                      where "database_name" = '<% database %>'
                        and "schema_name" = 'GEN' and "name" = 'WOA_OPS_AGENT');
    if (n = 0) then
        alter snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
            add agent <% database %>.GEN.WOA_OPS_AGENT;
        return 'added to Snowflake Intelligence';
    end if;
    return 'already listed in Snowflake Intelligence';
end;
$$;
