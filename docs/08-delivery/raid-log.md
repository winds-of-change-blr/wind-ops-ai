# RAID Log

> **Status:** Draft v0.5 · **Owner:** NK · **Last updated:** 2026-09-18
>
> **v0.7** fixes `I-13`, largely resolves `I-12`, and raises `I-15` (61.6% undetermined) and
> `I-16` (key-pair on `NIRAJ`).
>
> **v0.6** closes `Q-55` (anomaly granularity), states the `T-18` bound, and raises `I-13`
> (every published risk score is ~0 — found by the `T-18` degeneracy guard) and `I-14` (the detector
> was verified on a personal account, not the deploy account).
>
> **v0.5** closes `R-7`, `DEP-2` and `Q-39` (Streamlit verified in-account), answers `Q-12` in full,
> and adds `R-29` (Streamlit's ceiling, now a chosen constraint) and `Q-94` (revisit SAR if paid).
>
> **v0.4 adds** `A-20` (baseline-rule integrity) and `Q-90`…`Q-93` (practitioner call, baseline signal,
> aggregate figure definition, cold external scorer).
>
> **The single register.** Every risk, assumption, issue, dependency and open question in the plan is
> here. If it is not here, it is not tracked.
>
> Prefixes: `R-` risks · `A-` assumptions · `I-` issues · `DEP-` dependencies · `Q-` open questions.
> Reference-solution-specific risks keep their `R-REF-` prefix and live in
> [reference-solution-analysis.md §8](../00-hackathon/reference-solution-analysis.md#8-risks-created-by-differentiating).

---

## 1. Risks

Impact × likelihood, both High / Medium / Low.

| ID | Risk | I | L | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| `R-1` | **Scope against review and decision load.** The plan grew by three capabilities (`M9`, `M10`, `M11`). Person-hours are no longer the measure; **human review and decision capacity is** | H | **H** | Pre-committed [cut order](../02-functional/scope.md#cut-order) and dated [cut triggers](project-plan.md#8-cut-triggers). Review load named per item in [project-plan §7](project-plan.md#7-review-and-decision-load) | NK |
| `R-2` | **The label is not learnable.** Generator produces data no model can learn from. Everything downstream depends on this | **H** | M | Build it first. `T-10` on D4 is a hard gate. Two baselines, not one | SA |
| `R-3` | **Label leakage.** Back-filling trends behind known failures makes metrics look excellent and the system worthless | **H** | M | Split by component and time, never by row. Treat a suspiciously good result as a bug ([ADR-0006](../03-architecture/decisions/adr-0006-synthetic-data.md)) | SA |
| `R-4` | **Model no better than a trivial threshold rule** — we would be shipping a rule with a nicer name | **H** | M | `T-10`'s second baseline. If it fails, tune noise or improve features; do not relabel | SA |
| `R-5` | **4th member never joins.** `EP-8` unowned; registration closes 30 Sep | M | **H** | Plan assumes three. `EP-8` falls to NK, app collapses to one page | NK |
| `R-6` | **Credits exhausted.** $400 shared. **CoCo token spend is the largest consumer so far** — planning alone cost ≈16.75 credits, 90% of it tokens | H | M | Sum both sources when reporting; 6-month window, `XSMALL`, `AUTO_SUSPEND=60`, resource monitor, report at each $100 band. Keep exploratory chat sessions bounded | NK |
| `R-7` | ~~**Streamlit unavailable on trial account**~~ (`Q-39`) | — | — | **Closed 2026-09-18.** `CREATE STREAMLIT` verified working on this account. See [`ADR-0020`](../03-architecture/decisions/adr-0020-app-platform.md) | NK |
| `R-29` | **Streamlit's layout and interactivity ceiling weakens `E8`** — visual appeal is our thinnest dimension, and we have now *chosen* this constraint rather than inherited it | M | M | The one reusable evidence panel (fewer bespoke layouts, not more); the funnel via `st.components` HTML or Vega-Lite, degrading to a stacked bar that still carries the number; precomputed engine tables so no widget triggers expensive recompute | NK |
| `R-30` | **Trial-account objects do not survive.** On 2026-09-24 the deploy account was found **empty**: the database, the nine `WOA_*` roles and both warehouses recorded in `STATE.md` §5 two days earlier were gone, and everything had to be re-deployed | Medium | High — a demo-day disappearance would be fatal | Every object is created by a `just` recipe, so recovery is one command (`deploy-foundation` → `deploy-data` → `seed` → `verify`, ~15 min). **Rehearse that recovery before the demo** and never rely on state persisting overnight | SB |
| `R-31` | **CoCo and the CLI are on different Snowflake accounts.** The conversation bills to `HHWOUEB-WQ04283`; `snow` deploys to `JKDRJBB-MW27072`. Neither account alone shows what a session cost | Certain | Medium — cost under-reporting, and `Q-41` (who holds the elevated credential) is now open against a *different* account than when it was raised | Always sum both sources, as `STATE.md` §6 does. Re-point `Q-41` at the correct account before any shared-environment work | NK |
| `R-8` | **Cross-region inference disabled**, so `claude-sonnet-4-5` stops resolving | M | L | `llama3.1-8b` verified in-region. Rehearsed in the [runbook](../03-architecture/deployment.md#7-demo-day-runbook) | SA |
| `R-9` | **Late submission.** Uploading near the deadline; the organiser carries no responsibility | **H** | M | Submit D15 (2 Oct), keep D16–17 as buffer with no planned work | NK |
| `R-10` | **Metrics disagree** across app, semantic view and agent — the most credibility-destroying defect available | H | M | One definition per metric; `T-24` parity test | JP |
| `R-11` | **Time sunk into the app** at the expense of the engine, because the UI is what judges see | M | M | Gates G1–G4 all precede the surface phase. App starts D12 | NK |
| `R-12` | **Demo failure on the day** | H | M | Runbook with per-step fallbacks; five golden scenarios so one bad asset is survivable; rehearse twice |  NK |
| `R-13` | **Shipping our own version of a defect we criticised** | **H** | L | The twelve gating tests each encode a specific reference-solution failure | JP |
| `R-14` | **Scope creep via `Could` items**, especially Marketplace and MCP for bonus points | M | M | `Could` items are unplanned by design. Only after every Must is done | NK |
| `R-15` | **PR review becomes the bottleneck** — 2 approvals required, 3 active people, 2 h/day | M | M | Open PRs early; batch review into the daily slot; never end a session with a broken `main` | NK |
| `R-16` | **Over-claiming in the deck.** Easy to write "AI-powered predictive maintenance" and mean less | H | L | "What we are not claiming" in the [business case](../01-business/business-case.md#7-what-we-are-not-claiming) and [ML doc](../05-ai-ml/ml-models.md#9-what-we-will-not-claim); deck reviewed against them | NK |
| `R-17` | **Judging criteria change** mid-contest; the organiser may modify rules at any time | M | L | Watch announcements. `E1`–`E9` from problem-statement.md remains our operative scorecard | NK |
| `R-18` | **Wind-domain error** spotted by a knowledgeable judge | M | M | Profile carries a cited source list; anything invented is marked *(illustrative)*; Turbine OEE declared as our proposal | NK |
| `R-19` | **Over-suppression hides a real failure.** `M9`'s whole value proposition inverts if the classifier silences something that mattered | **H** | M | **`T-60` — gating, zero tolerance.** Plus `FR-32`'s guards, and the `UNDETERMINED` class exists precisely so ambiguity is disclosed rather than resolved as noise | JP |
| `R-20` | **Compression becomes a vanity metric.** A 40:1 ratio is trivially achieved by suppressing everything | M | M | `FR-68` makes the anti-gaming pairing structural: compression is never rendered or exported without the real-failures-suppressed count beside it. `T-70` asserts it at view level | JP |
| `R-21` | **Schedule suggestions read as implausible to a planner.** Constraints can be tested; credibility cannot | M | **H** | Highest review-load item; 2–3 review rounds budgeted around D11. `T-71` guarantees they are at least *feasible*; only NK can judge whether they *persuade* | NK |
| `R-22` | **The action service becomes a D12 bottleneck.** Four decision types now converge on one write path | **H** | M | Deliberate — one audited path is the architecture. D12 is named as the second pivot, with cut-order steps 3 and 4 available the same day | NK |
| `R-23` | **The scheduled run breaks `NFR-3`** by inheriting a human's `ACCOUNTADMIN` default role | M | M | `WOA_SCHEDULER` named on **D1**, not D14. `T-78` asserts the effective role | NK |
| `R-24` | **MCP fails live during the demo** | L | M | Optional by design; `T-79` proves approval works without it; **first in the cut order**; skipped without comment if it fails | NK |
| `R-25` | **The submission is unreadable rather than unbuilt.** A judge gives an entry 5–15 minutes, lands on the repo `README`, and will not read `docs/`. Effort has gone into artefacts that do not score | **H** | M | `M13` makes the README, walkthrough, results summary and deck **Musts**. **`T-89`** — a non-author must reach a working system from the README. The deck is drafted **D1** | NK |
| `R-26` | **We look visually plain** beside a team shipping glassmorphism, and lose `E8` Design on aesthetics despite better substance | M | **H** | One striking, honest visual: **the alarm funnel** (`FR-90`). Plus one reusable evidence panel used consistently. We will not out-pretty; we will out-communicate | NK |
| `R-27` | **Our honesty costs us on a checklist read.** The brief says "**real time**"; we would otherwise have said "refreshed daily" while competitors batch-load and claim real time | M | M | **`M12`** restores one incremental path with a declared lag, so the honest phrasing is also the accurate one. This was a deliberate reversal of an earlier decision | NK |
| `R-28` | **`E2` collapses if `T-10` fails.** Forty percent of the score rests on the label being learnable | **H** | M | D4 gate, and the second baseline (beating a trivial rule) is part of the test rather than an afterthought. If it fails, the honest response is a smaller true entry — not a relabelled rule | SA |

**The two that matter most:** `R-1` and `R-2`. `R-1` is certain and managed by cutting. `R-2` is
existential and managed by building the generator first and testing it on D4.

## 2. Assumptions

Each is something we believe and have not proven. If one is wrong, work changes.

| ID | Assumption | If wrong | Verify by |
| --- | --- | --- | --- |
| `A-1` | 2 h/day per person is sustainable across 15 days including weekends | Cut deeper and earlier | D5 (`Q-65`) |
| `A-2` | Verified platform capabilities remain available and behave the same at scale | Degraded modes per container | D9 |
| `A-3` | $400 is enough for 6 months of data, model training and search indexing | Reduce window and volume | D5, at the first $100 band |
| `A-4` | Judges may know the reference solution, but will not have read its source | Differentiation must stand alone regardless — which is why we never mention it (`R-REF-5`) | — |
| `A-5` | Synthetic data is acceptable to judges, given the brief itself recommends generating it | — | Stated in the brief; low risk |
| `A-6` | A deck plus a documented repo is the complete prototype submission | Re-read Official Rules §4.5 before D14 | D14 (`Q-2`) |
| `A-7` | The profile's *(illustrative)* figures may be changed without contradicting it | The profile says so explicitly | Settled |
| `A-8` | `SNOWFLAKE.ML.CLASSIFICATION` feature importances are sufficient as "drivers" | Attempt SHAP, or describe drivers more narrowly | D8 |
| `A-9` | 40–60 seeded failures support a credible held-out evaluation | Raise failure rate, not window | D4 (`Q-42`) |
| `A-10` | One agent is enough; multi-agent adds no capability here | Reconsider only if a Must needs it | Settled by decision |
| `A-11` | The audit-first write pattern is fast enough to feel instant in a demo | Measure; optimise the procedure, never remove the audit | D12 |
| `A-12` | Nobody on the team needs to learn Snowflake ML from scratch | Add a spike day; cut a Should | D1 |
| `A-13` | **Four alarm sources are enough** to make a compression figure credible. Three are derived from data we already generate | Add a fifth source; the schema accepts one without change | D5 |
| `A-14` | **A fixed grammar can parse the free-text constraints a planner would realistically type** | Involve the model in translation only — never in feasibility (`Q-76`) | D11 |
| `A-15` | **A notification integration can deliver the digest server-side from a scheduled task** | Digest becomes an in-app page; the pre-shift value is lost and we say so | D14 |
| `A-16` | **Seeded chattering, grid-dip and code-cascade patterns are realistic enough** that detecting them means something | Tune the generator; report the noise parameters honestly | D6 |
| `A-17` | **Judges will not read `docs/`.** The deck, README, walkthrough and results summary carry the score | If a judge does read deeply, we gain — the asymmetry is in our favour, so this assumption is safe to act on | — |
| `A-18` | **One striking visual is enough** for `E8`. A second would compete with `E2` for build time | Add a second only if `M2`/`M3` land early (`Q-85`) | D13 |
| `A-19` | **A generated results summary reads as more credible than a written one** | If it reads as raw and unfriendly, add framing prose around the generated figures — never replace them | D15 |
| `A-20` | **The trivial baseline rule we define is genuinely the one an engineer would reach for.** If we pick a weak rule, the comparison in `FR-97` flatters the model and the strongest claim we own becomes the same species of dishonesty we differentiate against | Define the rule on **D8, before the comparison is run**; state the rule explicitly on deck slide 9 so a judge can judge its fairness | D8 |

## 3. Issues

Live problems, as opposed to risks.

| ID | Issue | Impact | Action | Owner |
| --- | --- | --- | --- | --- |
| `I-1` | **`terms-and-conditions.md` is built from the wrong source** — the generic hack2skill legacy terms, not this contest's Official Rules. It differs materially on team size (2–6 vs **1–4**), IP (6-month right of first refusal vs **none**), attendance (disqualification clause **absent** from the real rules), presentation format, and judging criteria | Three planning assumptions were wrong | **User decision: do not correct it.** `problem-statement.md` takes priority. Recorded here so the team knows the discrepancy exists | NK |
| `I-2` | **`company-profile.md` §6 and §12 are out of date** relative to the persona set: two roles were collapsed onto one persona each, and four new roles were requested | Cosmetic, but the profile self-describes as needing this update | Proposal in [personas §1.1](../01-business/personas-and-journeys.md#11-mapping-back-to-the-profile-and-two-deliberate-splits). Not edited — read-only | JP |
| `I-3` | **Account edition unreadable**, so credits cannot be converted to dollars exactly | Cost reporting is approximate | Report **credits** as the hard number, dollars as an estimate. Parked by user | NK |
| `I-4` | **`P-4` (Field Technician) has no story** — `FR-50` is priority `C2` and would not survive the cut | One persona unserved | `Q-34`: promote `FR-50`, or accept and say so | JP |
| `I-5` | **Estimates are unvalidated** first-pass numbers by one person | The 164 h figure may be wrong in either direction | **Resolved by removal.** Person-hour estimates have been dropped from the plan; the constraint is now review and decision load ([project-plan §7](project-plan.md#7-review-and-decision-load)) | SA |
| `I-6` | **`S2` and `S3` remain as pointer rows** in scope after promotion to `M9` and `M10` | Slight redundancy in the scope document | Deliberate — removing them would break existing cross-references. They resolve to their new homes | NK |
| `I-7` | **The model is probably too good for the data to be credible.** Held-out component precision **1.000** and PR-AUC **0.988**. No leakage found: features are observable-only, the split is component-disjoint, and `DQ-NO-ID-FEATURE` is green. [`ml-models.md`](../05-ai-ml/ml-models.md) §8 says to treat a suspiciously good result as a bug | A judge may reasonably not believe the number, and [`ADR-0006`](../03-architecture/decisions/adr-0006-synthetic-data.md)'s honesty constraint is not satisfied in spirit even though `T-10` passes | **Raise generator noise** — the CMS cubic damage term makes band energy nearly determine failure. Do it in the generator, not the model, and re-run `T-8` and `T-10` together. Tracked as `Q-84` | SA |
| `I-8` | **Drivers are not model feature importances.** `RISK_CLASSIFIER!SHOW_FEATURE_IMPORTANCE()` and `!SHOW_EVALUATION_METRICS()` both fail with `Computation Error` in this account, reproduced on a freshly trained probe model with default config | Weaker than [`ml-models.md`](../05-ai-ml/ml-models.md) §6 specifies. `FR-18` and `T-16` are satisfied, but the explanation is a feature-level discriminability score, not an attribution | Every row records `IMPORTANCE_METHOD` so no surface can overclaim. Either raise with Snowflake, or amend §6 to describe what we actually ship. **Must not be described as SHAP or as per-prediction** | SA |
| `I-9` | **`04-code.md` §7 anticipates `python/generator/` and `python/ml/`; both layers are set-based SQL and `python/` does not exist.** Defensible (`ADR-0007` chose `SNOWFLAKE.ML.CLASSIFICATION`, §9 says engine logic stays in SQL, and the work is bulk set manipulation) but the code layout now contradicts the build | A reader following the plan looks for code that is not there | Update [`04-code.md`](../03-architecture/04-code.md) §7, **or** write an ADR recording the choice. Recorded in `STATE.md` §7 meanwhile | NK |
| `I-10` | **ML features read `RAW` directly, not `CURATED`**, because the curated layer does not exist yet (`US-9`, `US-11`, `US-12`, `US-93`) | The matched-band control `US-9` calls for is satisfied only because the generator writes `rpm_band`/`load_band` onto CMS rows. If curation later re-bands differently, features and curation will disagree | Revisit when `20_curate` lands; `T-3` is the test that will catch a divergence | SB |
| `I-11` | **`just pr` uses `--fill`, so any PR with more than one commit is titled after the branch.** PR #5 was created as *"feat/sb/synthetic data generator"* and both #5 and #6 needed their title and body set afterwards | Every multi-commit PR gets a poor title unless someone remembers to fix it | Pass `--title` and `--body-file` instead of `--fill`, or generate the body from the commits. Small, and worth doing before the submission PRs | SB |
| `I-12` | **`T-94`, `T-86` and `T-87` have their numbers but no surface.** The baseline comparison, the alarm funnel and the held-out metric are all recorded in `OPS` and all three are **gating** | Three gating tests cannot pass until the app exists, so `G5` is blocked behind `deploy-app` | Build the evidence panel first, as [`project-plan.md`](project-plan.md) D13 already sequences it. **Largely resolved 2026-09-26:** the app now shows the funnel, the held-out metric and the rule-versus-model comparison, all read from `OPS`/`ENGINE`. `T-86`/`T-87`/`T-94` still need their UI-reconciliation assertions written | NK |
| `I-13` | ~~**Every published risk score is ~0, so the triage surface is empty.**~~ **FIXED 2026-09-26** in `feat/nk/app-and-serving`. Scores are now published *as of* `window_end − horizon` (`ML.V_SCORING_ASOF`), the last date whose 30-day outcome is knowable. Variance 1e-12 → 0.0148; 6 components HIGH. No generator change, and `T-10` (measured on the held-out split) is untouched. `DQ-RISK-SURFACE` now fails the build if it regresses | Closed | The app labels every risk figure with its as-of date, so it never implies the scores are "today" | NK |
| `I-14` | **The anomaly detector was built and verified on a personal account, not the deploy account.** `snow` was absent from NK's machine and `~/.snowflake/connections.toml` has no `JKDRJBB-MW27072` entry, so the stack was re-deployed from the recipes into `EXKFAFL-NW77746`. The reproduction matched closely — 108,317,900 signal rows against 108,339,384, 58 seeded failures, `T-10` at 1.7647× against 1.71× — which is itself evidence the recipes are account-agnostic and deterministic | The code is proven to run and the arithmetic is proven to hold, but **no figure in evidence 06 is yet a fact about the project's own account**. `STATE.md` §5 must not absorb these object lists as if they were on the deploy account | Re-run `just deploy-ml` on `JKDRJBB-MW27072` when a credential is available, and confirm `T-18` passes there. Cheap — one command. Blocked behind `Q-41` (who holds the elevated credential), which `R-31` already re-pointed at the new account | NK |
| `I-15` | **The undetermined rate is 61.6%.** 9,739 of 15,803 incidents are `UNDETERMINED`, because the classifier now refuses to call anything noise on a component nothing monitors — converters, yaw, blades and component-less alarms have no model coverage. That is ADR-0017 working as designed, and the first cut that ignored it hid 9 real failures (`T-60`) | Honest but unflattering on screen, and it means operators still see ~9,700 items needing a human | Extend detector coverage beyond GBX/GEN/MSB/PIT; that shrinks the rate by *earning* nuisance calls rather than guessing them. **Never** lower the rate by relaxing the evidence rule | SA |
| `I-16` | **A JWT key-pair was added to user `NIRAJ` on `BGTCHIX`** so the `snow` CLI can run recipes non-interactively. Private key at `~/.snowflake/keys/woa_bgtchix_key.p8`, outside the repo | A credential now exists that did not before | Other teammates need their own key-pair or connection to deploy here; rotate or `UNSET RSA_PUBLIC_KEY` after the hackathon | NK |
| `I-17` | **External access is not supported on this trial account.** `CREATE EXTERNAL ACCESS INTEGRATION` fails outright, so the app can never install a package from PyPI, and nothing in the account can make an outbound call. It surfaced when the app failed to boot: the container runtime requires a `pyproject.toml`, and a `--prune` redeploy had deleted the runtime's default one | The app is limited to the runtime's pre-installed packages (streamlit, pandas, altair, snowflake-connector-python). **It also bears on `ADR-0019`**: any MCP or webhook path needing egress from Snowflake is unavailable here, so the notification integration route must be re-verified before it is relied on | Ship `app/pyproject.toml` with `dependencies = []`. Re-probe notification integrations early, not on D14 | NK |

## 4. Dependencies

| ID | Dependency | Needed by | Fallback |
| --- | --- | --- | --- |
| `DEP-1` | 4th member confirmed **and registered** | 30 Sep (D13) | Three-person plan; `EP-8` to NK |
| `DEP-2` | ~~Streamlit object creation on this trial account~~ (`Q-39`) | — | **Closed 2026-09-18** — verified working |
| `DEP-3` | `CORTEX_ENABLED_CROSS_REGION` stays `ANY_REGION` | D11 | `llama3.1-8b` in-region |
| `DEP-4` | $400 credit not exhausted | D15 | Reduce volume; suspend everything idle |
| `DEP-5` | Verified platform features remain available | D9 | Per-container degraded modes |
| `DEP-6` | Two PR reviewers available daily | daily | Batch review in the daily slot |
| `DEP-7` | Organiser submission portal available and understood | D15 | Submit early; screenshot confirmation |
| `DEP-8` | **`WOA_SCHEDULER` named, and its default role set** | **D1** | The automation cannot be created without breaking `NFR-3` |
| `DEP-9` | **MCP target workspace and credential** | D13 | `FR-84` cut — it is first in the cut order anyway |

## 5. Open questions

Seventy-two, grouped by what they block. **Blocking** means work stops without an answer.

### Blocking

| ID | Question | Owner | Needed by |
| --- | --- | --- | --- |
| `Q-5` | Who is the 4th member, and what do they own? | NK | 30 Sep |
| `Q-27` | History window — 6 months plus a failure-rich period? ([ADR-0016](../03-architecture/decisions/README.md#adr-0016--history-window)) | SA | D1 |
| `Q-30` | Which component classes get a model? ([ADR-0014](../03-architecture/decisions/README.md#adr-0014--model-granularity)) | SA | D2 |
| `Q-39` | ~~Can we create a Streamlit object on this trial account?~~ | **Closed 2026-09-18 — yes, verified.** Platform question settled in [`ADR-0020`](../03-architecture/decisions/adr-0020-app-platform.md) | — |
| `Q-94` | If the account becomes paid, do we revisit Snowflake App Runtime? Recommendation: **not during the hackathon, and not after D2.** Recorded so the decision is deliberate rather than forgotten | NK |
| `Q-78` | **`WOA_SCHEDULER`: confirm the role name and that its default role is set correctly** | NK | **D1** |
| `Q-79` | **MCP target — which workspace, and who holds the credential?** | NK | D13 |

### Answered

| ID | Question | Answer |
| --- | --- | --- |
| `Q-1` | Are judging weightings published? | **Yes** — 30% Real-World Relevance, 40% Technical Execution, 30% Solution Completeness (event page). `problem-statement.md`'s `E1…E9` remains our operative scorecard by user decision |
| `Q-6` | Hours per day? | **2 h/day** per person |
| `Q-8` | Where are skills published? | Kept in-repo for now; published later |
| `Q-9` | Correct `terms-and-conditions.md`? | **No.** `problem-statement.md` takes priority. See `I-1` |
| `Q-7` | Account edition? | **Parked.** Not readable; design to the lowest capability set. See `I-3` |
| `Q-12` | Streamlit and compute pool on trial? | **Fully answered 2026-09-18.** Streamlit ✓; compute pools ✓ (created `CPU_X64_XS`); plain SPCS `CREATE SERVICE` ✓; **`APPLICATION SERVICE` ✗ — blocked on trial accounts**, so Snowflake App Runtime is unavailable to us ([`ADR-0020`](../03-architecture/decisions/adr-0020-app-platform.md)) |
| `Q-24` | Cut order accepted? | **Yes**, and superseded by the v0.2 cut order after `M9`–`M11` were promoted |
| `Q-64` | Ownership split accepted? | **Yes**, with `EP-11` and `EP-12` added to NK and `EP-5` to JP |
| `Q-35` | Do the hour estimates survive contact with the team? | **Moot.** Estimates removed; the constraint is review and decision load |
| `Q-18` | Which stretch KPIs do we commit to? | **Mean time to respond** — it falls out of `M9`'s acknowledgement timestamps |

### Contest and process

| ID | Question | Owner |
| --- | --- | --- |
| `Q-2` | Re-check the Official Rules before submission — the organiser may amend them | NK |
| `Q-3` | Confirm team leader and every member's registration | NK |
| `Q-4` | Repository licence compatibility with the Official Rules' non-exclusive licence grant | NK |
| `Q-10` | Provenance of `problem-statement.md` §2–3, which appear in neither the event page nor the Official Rules | NK |
| `Q-11` | Do we add a CLI-run component and a Marketplace angle for Official Rules §9 bonus consideration? | NK |
| `Q-13` | 4th member registered by 30 Sep | NK |
| `Q-25` | Marketplace weather (`C9`) — worth the credits? | NK |
| `Q-40` | Set an account resource monitor? | NK |
| `Q-41` | Who holds the one-time elevated credential, and where? | NK |
| `Q-69` | Make setup and scoring demonstrably CLI-invokable? | NK |

### Business and scenario

| ID | Question | Owner |
| --- | --- | --- |
| `Q-16` | Confirm energy tariff and capacity factor, or keep them *(illustrative)* | NK |
| `Q-17` | Does lost energy belong in our value story, given it is the customer's revenue? | NK |
| `Q-18` | Which stretch KPIs do we commit to? | JP |
| `Q-19` | Model DSM penalties, or keep as context? | SA |
| `Q-20` | Accept the persona splits and the profile-update proposal? | JP |
| `Q-21` | `P-4` job pack — own surface, or printable panel? | JP |
| `Q-22` | One role-filtered fleet view, or a distinct `P-1` surface? | NK |
| `Q-23` | Power curve per platform, or drop `GS-5`? | SA |
| `Q-28` | One page or a navigation? | NK |
| `Q-34` | Promote `FR-50`, or accept `P-4` unserved? See `I-4` | JP |

### Data and model

| ID | Question | Owner |
| --- | --- | --- |
| `Q-14` | UNS keys as primary, or the profile's IDs with UNS as an attribute? | JP |
| `Q-15` | One classifier or per-class? (folded into `Q-30`) | SA |
| `Q-26` | How many synthetic documents? | JP |
| `Q-29` | What margin defines "learnable"? | SA |
| `Q-31` | Weather as forecast or synthetic constraint? | JP |
| `Q-42` | Are 40–60 seeded failures enough? | SA |
| `Q-43` | Generate oil-debris counts? | SA |
| `Q-44` | Invent an alarm code list, or map to a standard? | JP |
| `Q-45` | Does the schedule-deviation model survive the cut? | SA |
| `Q-46` | `FCT_SIGNAL_10MIN` long or wide? | JP |
| `Q-47` | Feature grain — daily or hourly? | SA |
| `Q-48` | Model curtailment separately from grid outage? | JP |
| `Q-52` | One horizon or two? | SA |
| ~~`Q-53`~~ **CLOSED 2026-09-25** | Which precision/recall operating point? **`p >= 0.50` at component level** — see [`ml-models.md`](../05-ai-ml/ml-models.md) §10 | SA |
| `Q-54` | Attempt per-prediction SHAP? | SA |
| `Q-55` | ~~Anomaly detector per instance or per class?~~ **CLOSED 2026-09-25 — per instance** (`SERIES_COLNAME = COMPONENT_ID`). The per-class recommendation rested on "fewer models to train", which is void: multi-series is one model object either way. [`ml-models.md` §10](../05-ai-ml/ml-models.md#10-open-questions) | SA |

### Semantic layer, agent, quality

| ID | Question | Owner |
| --- | --- | --- |
| `Q-32` | Allowlist by object, operation, or both? | NK |
| `Q-33` | Is 5 s p95 achievable on `XSMALL`? | JP |
| `Q-49` | CMS grain exposed to the semantic view? | JP |
| `Q-50` | Similar-failure search — tool or semantic view? | JP |
| `Q-51` | How many verified queries can we author and validate? | JP |
| `Q-56` | Keep `read_similar_failures` as a tool? | JP |
| `Q-57` | May the agent propose a suppression? | NK |
| `Q-58` | Which skills do we publish? | NK |
| `Q-59` | Validator: parse SQL, hard read-only role, or both? | NK |
| ~~`Q-60`~~ **CLOSED 2026-09-25** | Margin for "beats the trivial rule"? **>=1.25x component precision at no-lower recall**; measured 1.71x — see [`testing-and-validation.md`](../07-quality/testing-and-validation.md) §open questions | SA |
| `Q-84` | **Do we raise generator noise to make the model's score credible?** Held-out precision 1.000 / PR-AUC 0.988 with no leakage found. `ADR-0006`'s honesty constraint wants a trivial rule that does *not* match the model; ours is beaten 1.71× but the absolute numbers look too clean. Recommendation: **yes, raise noise in the CMS damage term**, and re-run `T-8` and `T-10` together since they pull in opposite directions | SA |
| `Q-61` | Can `T-24` parity be fully automated? | JP |
| `Q-62` | Adversarial suite per change or per milestone? | SA |
| `Q-63` | Are 59 tests realistic at this capacity? | NK |

### Delivery

| ID | Question | Owner |
| --- | --- | --- |
| `Q-35` | Do the estimates survive contact with the team? See `I-5` | SA |
| `Q-36` | Spike the matched-band join on D2? | JP |
| `Q-37` | Split the constraint-engine story? | JP |
| `Q-38` | Who owns `EP-10` submission? | NK |
| `Q-65` | Is 2 h/day realistic on weekends? | NK |
| `Q-66` | Who are the two PR reviewers with three active people? | NK |
| `Q-67` | Evidence per session or per story? | NK |
| `Q-68` | Three skills, or one excellent one? | NK |
| `Q-70` | Does the submission portal want a video, or only a deck and repo link? | NK |
| `Q-71` | Who presents at the Finals if shortlisted? | NK |
| `Q-72` | Do we record a walkthrough as a deck asset? | NK |

### Alarm intelligence, scheduling and ingenuity (v0.2)

| ID | Question | Owner |
| --- | --- | --- |
| `Q-73` | Alarm severity taxonomy — one scale across all four sources, or per-source with a mapping? Recommendation: map to one 4-level scale, retain the source's own value | JP |
| `Q-74` | Flood threshold — fleet-wide, per site, or per operator? Recommendation: per site | JP |
| `Q-75` | Does `GS-5` survive now that `C3` is dropped? | SA |
| `Q-76` | Free-text parsing — fixed grammar, or model-assisted? Recommendation: grammar first | SA |
| `Q-77` | Compression shown as two numbers, or a ratio with a caveat? Recommendation: two numbers, side by side, equal weight | NK |
| `Q-80` | Does the digest go by email, webhook, or both? Verify which integration types this account supports **before D14** | NK |
| `Q-81` | Who authors the two reason vocabularies? Recommendation: JP for alarm dismissals, NK for schedule rejections — each needs its own domain framing | JP |
| `Q-82` | Chattering window and trip-count thresholds — fixed, or per alarm code? Recommendation: fixed first, per-code only if it produces obvious false labels | JP |
| `Q-83` | Standing-alarm threshold — how long is "nobody acting"? Recommendation: 48 h, tuned once real seeded data exists | JP |

### Scoring surface and evaluation (v0.3)

| ID | Question | Owner |
| --- | --- | --- |
| `Q-84` | Do we show the criteria-traceability matrix to judges, or keep it internal? Recommendation: internal, but let it drive the deck's slide order | NK |
| `Q-85` | Is one striking visual enough for `E8`, or do we need two? Recommendation: one, done well | NK |
| `Q-86` | Which single figure leads the results summary? Recommendation: **lift over the trivial rule** | SA |
| `Q-87` | Do we publish the undetermined rate even if it is high? Recommendation: **yes** | NK |
| `Q-88` | Which incremental path does `M12` use — alarms or CMS features? Recommendation: **alarms**, since it feeds the opening demo beat and makes freshness visible where a judge is already looking | JP |
| `Q-89` | Who is the non-author who tests the README for `T-89`? Recommendation: whichever teammate did not write it; failing that, a colleague outside the team | NK |
| `Q-90` | **Who is the wind O&M or industrial-monitoring practitioner for the D2 sanity-check call?** We have **zero external signal** on whether the scenario reads as credible to someone who has done this work, and judges may include industry specialists. 20 minutes on `J-6` and `J-3`. If no practitioner can be found, say so on the honesty slide rather than implying validation we do not have | NK |
| `Q-91` | Which signal is the trivial baseline rule built on — CMS band energy, or bearing temperature? Recommendation: **band energy** (see `A-20`) | SA |
| `Q-92` | What exactly is the aggregate outcome figure — failures flagged of failures seeded, median lead time, and LD exposure identified? Recommendation: **all three in one sentence**, computed, never typed (`FR-98`) | NK |
| `Q-93` | Who performs the **cold external scoring run on D14** (`US-97`), and against which rubric copy? Recommendation: someone who has not seen the work, given only deck, README and walkthrough, scoring against `E1`–`E9` verbatim | NK |

## 6. Review cadence

| When | What |
| --- | --- |
| Daily standup | New issues; blocking questions; cut triggers |
| **D1** | **`WOA_SCHEDULER` decision** (`Q-78`, `DEP-8`); ~~Streamlit test~~ (**`Q-39` closed early**); **deck drafted as a specification** |
| **Any day** | **A deck slide that cannot be filled marks its feature as cut, that day** |
| D6, D9, D12 | Gate review — pass/fail, then apply the cut trigger if failed |
| **D11** | **Schedule suggestion quality review** — the highest review-load item (`R-21`) |
| At each $100 credit band | `R-6` review, summing CoCo tokens **and** warehouse credits |
| D14 | Full RAID review before submission; re-check `Q-2` |
| **D15** | **`T-89`** — a non-author runs the README; results summary generated; criteria traceability checked |
| At each $100 credit band | `R-6` review |
| D14 | Full RAID review before submission; re-check `Q-2` |
