-- =============================================================================
-- 70_agent / 01 — the Wind Ops agent (read-only)                  STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-30 (citations), US-31 (no destructive tools), US-32 (engine
--              candidates only), G3
-- Proves     : T-39/T-40 (claims cite a source), T-47/T-48 (no write tools)
-- Authority  : ADR-0011 (determinism boundary), ADR-0009, ADR-0010
-- Parameter  : <% database %>
--
-- Written as DDL, not through the agent-studio CLI (not installed here; same
-- decision NK took for the semantic view, 2026-09-26).
--
-- ===================== TWO TOOLS, BOTH READ-ONLY =============================
--
--   fleet_data         Cortex Analyst over SERVING.SV_WIND_OPS — numbers
--   maintenance_docs   Cortex Search over DOCS.CSS_MAINTENANCE_DOCS — procedures
--
-- There is deliberately no generic (UDF/procedure) tool. Every write in this
-- system goes through an approval-gated procedure (G4, ADR-0012); an agent that
-- could call one would be a way around the approval. T-48 asserts this list.
--
-- ===================== THE DETERMINISM BOUNDARY ==============================
--
-- The engine decides; the model explains. Risk scores, alarm classes and
-- expected loss come from the engine through the semantic view. The agent may
-- rank or compare them; it may not invent a score, reclassify an alarm, or
-- recommend suppressing one — the instructions below say so in those words.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace agent GEN.WOA_OPS_AGENT
  comment = 'Wind Ops AI assistant: answers fleet-risk, availability, LD and alarm questions from the semantic view, and maintenance-procedure questions from the document search, with citations. Read-only. SYNTHETIC DATA.'
  profile = '{"display_name": "Wind Ops Assistant"}'
  -- Keeps the USAGE grants from 70_agent/02 across a redeploy. This account
  -- accepts COPY GRANTS after the properties, not straight after the name.
  copy grants
  from specification
$$
models:
  orchestration: claude-sonnet-4-5

orchestration:
  budget:
    seconds: 180
    tokens: 16000

instructions:
  system: >
    You are the Wind Ops assistant for Vayuveda Wind Systems, a FICTIONAL Indian wind
    turbine OEM. All data and documents are synthetic. You help reliability engineers,
    site managers and the remote monitoring centre understand component risk,
    contractual availability, liquidated damages (LD) and alarm incidents, and find the
    approved maintenance procedure.
  orchestration: >
    Use fleet_data for any number: risk, expected loss, availability, LD exposure,
    incident counts, rankings. Use maintenance_docs for any procedure, policy, part
    lead time, crane requirement or contract definition. When a question needs both
    (for example "which component is at highest risk and how do we repair it"), call
    fleet_data first, then maintenance_docs for that component class.
    Risk scores, alarm classes and expected loss are decided by the engine. Report them;
    never invent, adjust or re-derive them, and never reclassify an alarm.
  response: >
    Be concise and lead with the answer. Money is in Indian rupees (INR); write lakh
    (L) or crore (Cr) for large amounts. Every procedural or policy claim must cite its
    source as document id and section, for example "VWS-MP-GBX-014 · 4. Procedure".
    Every number must come from fleet_data. If neither tool supports a claim, say you
    do not know rather than guessing.
    LD exposure is a run-rate estimate, never an invoice: say so when you report it.
    UNDETERMINED alarm incidents are left for a human on purpose; never describe them
    as noise.
    Never recommend suppressing, dismissing or acknowledging an alarm, and never claim
    to have created a work order or changed anything: you are read-only. Suppression
    and work orders are human decisions made in the Command Center with approval.
  sample_questions:
    - question: "Which components are at highest risk, ranked by expected loss?"
    - question: "What is our LD exposure by site, and which sites are below guarantee?"
    - question: "What is the approved procedure for an up-tower HSS bearing replacement on a VW-3.0?"
    - question: "Which component is at highest risk, and does its repair need a crane?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "fleet_data"
      description: >
        Fleet numbers from the Wind Ops semantic view (synthetic data): 30-day component
        failure risk, risk band, anomaly flag, top drivers and expected loss in INR per
        component; contractual availability per turbine; LD exposure run-rate and
        shortfall against guarantee per site; alarm incidents with their class
        (ACTIONABLE, UNDETERMINED, NUISANCE). Use for any count, ranking, total or
        comparison. Do NOT use for procedures, policies or how-to questions.
  - tool_spec:
      type: "cortex_search"
      name: "maintenance_docs"
      description: >
        Search over the synthetic maintenance library: repair procedures per component
        class (gearbox, generator, main shaft bearing, pitch, converter), the alarm
        handling and suppression policy, the condition-monitoring response SOP, and the
        availability and LD contract terms. Each result is one document section with its
        doc_id and section heading, which you must cite. Use for how-to, policy, part
        lead time, crane need and contract definitions. Do NOT use for fleet numbers.

tool_resources:
  fleet_data:
    semantic_view: "<% database %>.SERVING.SV_WIND_OPS"
    execution_environment:
      type: "warehouse"
      warehouse: "WOA_APP_WH"
  maintenance_docs:
    search_service: "<% database %>.DOCS.CSS_MAINTENANCE_DOCS"
    max_results: "4"
    title_column: "doc_title"
    id_column: "chunk_id"
    stage_path: "@<% database %>.DOCS.MAINTENANCE_DOCS"
    relative_path_column: "file_name"
$$;
