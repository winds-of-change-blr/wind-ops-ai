# Problem Statement & Evaluation Criteria

> **Status:** Reference · **Source:** Hackathon brief (screenshots shared with the team, 2026-09-15) and
> [Terms & Conditions](terms-and-conditions.md) · **Last updated:** 2026-09-15

Sections 1–3 are transcribed **as provided** in the brief. Section 4 combines every
evaluation input into one scorecard. If the organiser updates the brief, re-check the
wording here against the hackathon dashboard.

---

## 1. Problem statement — *Predictive Maintenance and OEE Command Center*

Manufacturers lose value to unplanned downtime because OT sensor data sits apart from ERP
and maintenance context.

Build a solution that converges IT and OT data to predict failures, automate work orders,
and lift Overall Equipment Effectiveness.

- Correlate real time sensor streams (vibration, temperature, RPM) with ERP and maintenance
  records
- Predict failures in advance and support root cause investigation in natural language
- Deliver a command center experience for alert triage and action

### Judging Focus

- Real World Relevance
- Technical Execution
- Solution Completeness

---

## 2. Snowflake CoCo Usage Guidelines

All hackathon solutions must use CoCo (CLI, Desktop app) across the full lifecycle, from
planning through development to execution and testing. Teams should be able to show CoCo in
each phase below, and judges will look for evidence of it at every stage.

**Planning:** Use CoCo to explore the data, frame the problem, draft the solution design, and
outline the data model, ontology, and workflow before any build begins.

**Development:** Use CoCo to build the pipelines, semantic views, models, agents, and
application code, iterating directly in the CLI or Desktop app rather than by hand.

**Execution:** Run and orchestrate the complete end to end solution through CoCo, including
scheduled or automated runs where the scenario calls for it.

**Testing and validation:** Use CoCo to validate outputs, test accuracy, handle errors and
edge cases, and confirm the solution behaves correctly before the demo.

### Recommended CoCo tasks to demonstrate

- **Synthetic data generation:** Generate realistic, referentially consistent synthetic or de
  identified datasets with CoCo so teams never need production data and can respect privacy
  from the start.
- **Data pipeline creation:** Build and orchestrate ingestion and transformation pipelines
  (for example dynamic tables, tasks, and streams) directly through CoCo, including
  incremental and near real time flows.
- **Semantic model and ontology authoring:** Use CoCo to infer and generate semantic views,
  verified queries, and the ontology from a schema, then validate them against natural
  language questions.
- **Streamlit report and app generation:** Scaffold and run a Streamlit report or application
  through CoCo to present insights and let users take action inside the solution.
- **Connecting to additional sources via MCP:** Wire in external systems and tools through MCP
  (for example Jira, Slack, Google Drive, or other MCP servers) so the agent can read from and
  act across those tools.
- **Document and unstructured processing:** Parse, extract, and enrich documents with CoCo and
  combine them with structured data for richer answers.

---

## 3. Ways to showcase ingenuity in CoCo tool usage

Beyond building reusable skills, teams can stand out by using these CoCo capabilities:

- **Reusable and shareable skills:** Publish custom skills or agent skills that other teams
  could reuse. Clearly documented, reusable skills remain the headline bonus.
- **MCP connectors to external tools:** Extend the solution by connecting CoCo to additional
  data sources and tools through MCP, turning read only analysis into cross tool action.
- **Automations and scheduled runs:** Use CoCo automations, such as scheduled tasks in the CLI
  and Desktop app or asynchronous runs, so the solution operates unattended on a schedule.
- **Custom tools and function calling:** Register custom tools or functions the agent can call
  to take real actions rather than only returning text.
- **Multi agent orchestration:** Coordinate several agents or skills into one workflow, with
  clear handoffs and shared context.
- **Working across surfaces:** Demonstrate the same solution across the CoCo CLI, Desktop app,
  and Snowsight Cloud Agents, and surface it through the Slackbot where useful.
- **Guardrails and graceful fallback:** Show validation, error handling, confidence checks, and
  governed behavior so the agent fails safely and stays trustworthy.

---

## 4. Evaluation criteria — consolidated scorecard

> This section is **our interpretation**, not organiser text. It combines three inputs: the
> problem-specific judging focus (§1), the CoCo lifecycle requirement and bonus (§2–3), and the
> general judging criteria in the [Terms & Conditions](terms-and-conditions.md#judging). No
> weightings were published, so treat all criteria as equal until the organiser says
> otherwise (tracked as `Q-1` in the [RAID log](../08-delivery/raid-log.md)).

| # | Criterion | Source | What judges will likely look for | Where we plan to prove it |
| --- | --- | --- | --- | --- |
| E1 | **Real World Relevance** | Brief | A believable plant scenario, the right personas, quantified downtime/OEE impact, and actions a maintenance team would actually take | [Business case](../01-business/business-case.md), [Personas](../01-business/personas-and-journeys.md) |
| E2 | **Technical Execution** | Brief | A working IT/OT convergence pipeline, real (not faked) predictions, sound agent design, and governance | [Architecture](../03-architecture/README.md), [ML models](../05-ai-ml/ml-models.md), [Agents](../05-ai-ml/agents-and-tools.md) |
| E3 | **Solution Completeness** | Brief | All 3 bullets covered end to end: correlate → predict + root cause in natural language → triage + **action** (work orders) | [Scope](../02-functional/scope.md), [Requirements](../02-functional/requirements.md) traceability |
| E4 | **CoCo across the full lifecycle** | Brief (mandatory) | Evidence of CoCo in planning, development, execution and testing | [CoCo usage plan](../06-coco/coco-usage-plan.md), [Evidence log](../06-coco/evidence/README.md) |
| E5 | **CoCo ingenuity (bonus)** | Brief | Reusable skills (headline), MCP, automations, custom tools, multi-agent, multiple surfaces, guardrails | [CoCo usage plan](../06-coco/coco-usage-plan.md) |
| E6 | **Impact** | T&C | How the project benefits the target audience | [Business case](../01-business/business-case.md) |
| E7 | **Creativity** | T&C | Ingenious solutions and original ideas | [Reference solution analysis](reference-solution-analysis.md) (differentiators) |
| E8 | **Design** | T&C | A well-thought-out blueprint, and a crash-proof front end with good UI/UX | [C4 docs](../03-architecture/README.md), [Testing](../07-quality/testing-and-validation.md) |
| E9 | **Execution** | T&C | A clear timeline and effective results from start to finish | [Project plan](../08-delivery/project-plan.md), [Demo & submission](../08-delivery/demo-and-submission.md) |

### Presentation format (from T&C)

A selected team gets **5 minutes** in total. That time must include a **live demo of at least
30 seconds** of the working prototype, plus Q&A with the judges. See
[Demo & submission](../08-delivery/demo-and-submission.md).
