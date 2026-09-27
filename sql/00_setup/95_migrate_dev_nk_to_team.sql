-- =============================================================================
-- 95_migrate_dev_nk_to_team.sql — ONE-OFF, already run on 2026-09-27
-- =============================================================================
-- Authority  : AGENTS.md > Deployment (one team database, no user suffix)
-- Account    : JKDRJBB-MW27072 only. Run as ACCOUNTADMIN.
--
-- Personal clones were retired. Rather than redeploy the whole stack, NK's
-- fully verified clone becomes the team database. RENAME keeps data, grants,
-- procedures and views (none of them embed the database name).
--
-- Four objects DO store the fully qualified name and must be recreated
-- afterwards, through the recipes:
--   SERVING.SV_WIND_OPS        just sql sql/30_serve/02_semantic_view.sql
--   DOCS.CSS_MAINTENANCE_DOCS  just deploy-agent (60_docs)
--   GEN.WOA_OPS_AGENT          just deploy-agent (70_agent)
--   APP.WOA_COMMAND_CENTER     just deploy-app
-- Then `just verify`. Kept in git as the record of how WIND_OPS_AI came to be;
-- it is not part of any recipe and must not be re-run.
-- =============================================================================

use role accountadmin;

alter database WIND_OPS_AI_DEV_NK rename to WIND_OPS_AI;
