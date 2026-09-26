# Development phase evidence

Entries go here as `<NN>-<short-slug>.md`, one file per CoCo session.
Copy [TEMPLATE.md](../TEMPLATE.md). Rules: [AGENTS.md](../../../../AGENTS.md#evidence).

| Entry | Date | Stories / tests | What it records |
| --- | --- | --- | --- |
| [01-foundation-setup.md](01-foundation-setup.md) | 2026-09-21 | `US-44`, `US-45` · `T-50`, `T-52` | `00_setup` and `90_teardown` behind `just deploy-foundation`. Local toolchain built from nothing; account move re-verified; two contradictions found in `04-code.md` §6; the batched-SQL rule disproved by execution. **Nothing deployed yet** |
| [02-data-layer-foundation.md](02-data-layer-foundation.md) | 2026-09-22 | `US-6`…`US-8` | `RAW` tables and dimension seeding behind `just deploy-data` |
| [03-synthetic-data-generator.md](03-synthetic-data-generator.md) | 2026-09-24 | `US-8`…`US-12` · `T-8`, `T-11`, `T-12` | The generator and its quality gate. Found the account **empty** and re-deployed; found `03_seed_dimensions.sql` had never actually run; pinned `snow sql` templating to `STANDARD` |
| [04-risk-classifier.md](04-risk-classifier.md) | 2026-09-24 | `US-19`, `US-20` · `T-14`…`T-17`, `T-19` | The classifier and its two pre-registered baselines. Headline **partly superseded by entry 05**. Platform defect: `!SHOW_FEATURE_IMPORTANCE()` errors, so drivers are a standardised mean difference |
| [05-t10-margin-and-operating-point.md](05-t10-margin-and-operating-point.md) | 2026-09-25 | `T-10` (gating) · closes `Q-60`, `Q-53` | Settles the `T-10` margin and operating point, and **corrects entry 04**. Three successive metric defects, each flattering a different side; the alleged model non-determinism withdrawn as measurement noise |
| [06-anomaly-detector.md](06-anomaly-detector.md) | 2026-09-25 | `US-22` · `T-18` · closes `G2` | The second independent signal. Bound **pre-registered before measurement** at \|Spearman ρ\| ≤ 0.50, measured 0.222. Its degeneracy guard found `I-13` — **every published risk score is ~0** — which no test aimed at it would have caught |
| [07-app-and-prerequisites.md](07-app-and-prerequisites.md) | 2026-09-26 | `M8` first cut · `T-60` (gating), `T-86`, `T-96`, `T-97` · fixes `I-13` | Whole stack on `BGTCHIX`, the serving and alarm layers, and the Streamlit app — executed headless, 0 exceptions. **`T-60` caught the first alarm classifier hiding 9 real failures**; fixed from ADR-0017's text, not by tuning |
| [08-semantic-view-docs-and-agent.md](08-semantic-view-docs-and-agent.md) | 2026-09-26 | `G3` · `US-27`…`US-32` · `T-37`, `T-42`, `T-48` (gating) | Semantic view, 9 maintenance PDFs as 43 section chunks, Cortex Search, and a read-only agent. **`DQ-DOC-SECTIONS` caught the parser dropping headings from 3 documents.** The agent refused a suppression request and cited the evidence against it |
