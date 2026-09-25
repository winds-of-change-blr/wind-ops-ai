# ML Models

> **Status:** Draft v0.1 · **Owner:** SA · **Last updated:** 2026-09-17
>
> Decisions: [ADR-0007](../03-architecture/decisions/README.md#adr-0007--ml-approach),
> [ADR-0014](../03-architecture/decisions/README.md#adr-0014--model-granularity).
> Depends entirely on [ADR-0006](../03-architecture/decisions/adr-0006-synthetic-data.md) — if the
> label is not learnable, nothing here means anything.

---

## 1. What we are predicting

| | |
| --- | --- |
| **Question** | Will this component fail within the next *H* days? |
| **Unit of prediction** | Component position × scoring day |
| **Horizon `H`** | 30 days, chosen because it is the lead time a planner actually needs — long enough to order a part, book a crew, and find a low-wind window |
| **Scope** | `GBX`, `MSB`, `GEN`, `PIT` — the four classes with real CMS coverage (`Q-30`) |
| **Output** | Probability, plus top drivers with magnitude and direction, plus model version |

**We say "four component classes", not "the turbine".** Overclaiming coverage is the kind of thing
that unravels in questioning.

## 2. Two models, deliberately separate

| Model | Answers | Technology | Verified |
| --- | --- | --- | --- |
| **Risk classifier** | "Is this heading for failure within `H`?" | `SNOWFLAKE.ML.CLASSIFICATION` | ✅ trained in our account 2026-09-17 |
| **Anomaly detector** | "Is this behaving unlike itself at matched conditions?" | `SNOWFLAKE.ML.ANOMALY_DETECTION` | ✅ trained in our account 2026-09-17 |

They are not blended into one score. The classifier only recognises failure modes present in
training; the detector catches novel behaviour it has never seen. Merging them would hide which is
firing, and a planner needs to know whether the system is saying *"this looks like a known bearing
failure"* or *"this is behaving oddly and I don't know why"* — those warrant different responses.

`T-18` asserts the two are **not collinear**. The reference solution would have failed that test
outright: its failure probability was a linear rescale of its health score, correlation −1.0 by
construction, so its two "signals" carried identical information.

### 2.1 The `T-18` bound, and what it is measured on

`T-18` says "correlation below a stated bound" and the plan did not state one. It is now stated, and
it was **pre-registered** — committed before the correlation was ever computed, the same discipline the
two `T-10` baselines got:

| | |
| --- | --- |
| **Bound** | **\|Spearman ρ\| ≤ 0.50** between risk probability and anomaly distance |
| Why 0.50 | ρ = 0.50 means ρ² = 0.25 shared rank variance, so at the bound three quarters of each signal is unexplained by the other. Any bound below 1.0 excludes the reference solution; 0.50 also excludes the far larger family of "technically two models, practically one" |
| Why Spearman | Risk probability is bounded and near-binary; anomaly distance is unbounded and long-tailed. Pearson across that pair measures tail shape as much as association. Pearson is recorded as context, never as the verdict |
| A null ρ **fails** | A constant anomaly score would make ρ null and pass a naive bound check while carrying no information. `DQ-NON-COLLINEAR` therefore requires ρ to be non-null **and** both signals to vary |
| Recorded as | A row in `ML.ML_INDEPENDENCE_SPEC` with `registered_before_evaluation = true`, so the ordering is auditable in data rather than only in git history |
| **Measured** | **ρ = 0.222** over 48,801 component-days (2026-09-25). Pearson 0.078 |

**The population is the whole detection window, not the planner's snapshot**, and the reason is
recorded because it looks like goalpost-moving and is not. The first implementation used
`SCORE_COMPONENT_RISK`; ρ came out 0.216 and **passed**, but the degeneracy guard failed the build
because published risk variance is 1e-12 — every component banded `MINIMAL`. A correlation against a
signal that does not vary describes nothing. The population changed; **the bound did not**. Both
numbers are recorded as metrics so the claim is checkable. The underlying defect is `I-13`.

## 3. Features

Built by `CMP-4` at `FEAT_COMPONENT_DAILY` grain, always **within matched operating bands**.

| Family | Examples | Why |
| --- | --- | --- |
| CMS band energy | Per monitored point and band, normalised within band | The primary degradation signal in real practice |
| Trend | Slope and acceleration over 7/14/30-day windows | Degradation is a *change*, not a level |
| Thermal | Bearing temperature rise above expected at matched condition | The profile's stated confirming signal |
| Cross-signal | Vibration-to-temperature divergence | Distinguishes mechanical wear from lubrication or cooling faults |
| Operating exposure | Hours at high load, start-stop count, cumulative revolutions | The damage driver |
| Context | Component age since install, platform, site stressor, hours since last intervention | `GBX` at coastal `TN-TVL` differs from `GBX` at `RJ-JSM` |

**Banding is not optional.** `g(operating point)` is large relative to `f(damage)` by design
([ADR-0006](../03-architecture/decisions/adr-0006-synthetic-data.md)), so an unbanded model learns
the wind. This is `US-9`, flagged as the subtlest data work in the build (`Q-36`).

Component **age since install** rather than turbine age is what makes genealogy pay off: a
refurbished gearbox in a 2016 turbine is a young part in an old machine.

## 4. Label

| | |
| --- | --- |
| Positive | A component-day within `H` days before a seeded failure on that component |
| Negative | A component-day with no failure within `H` |
| Excluded | Days after failure and before repair completion — the component is not in service |
| Expected balance | Heavily imbalanced. Roughly 40–60 failures × 30 positive days against ~1,000 components × ~180 days |

Imbalance is handled by reporting **precision and recall at an operating point**, not accuracy.
Accuracy on a dataset this imbalanced is trivially ~98% by predicting "no failure" always, which is
why it is not a metric we will quote.

## 5. Evaluation

| Aspect | Approach |
| --- | --- |
| **Split** | By **component instance and time**, never randomly by row |
| **Why** | Random row splits leak: adjacent days from one degradation ramp land in both train and test, and the model appears excellent while having learned nothing generalisable |
| **Primary metrics** | Precision and recall at a chosen operating point; PR-AUC |
| **Secondary** | Lead-time distribution — how many days before failure risk first crossed the threshold (`FR-19`) |
| **Baselines** | Two, both mandatory (see below) |
| **Reported** | To `OPS`, with model version, feature set, and training window |

### The two baselines

`T-10` requires beating both, and the second matters more:

1. **Stratified random.** A floor. Beating it proves only that something was learned.
2. **A trivial single-signal threshold** — e.g. "vibration band energy above the 95th percentile".
   **If the classifier does not clearly beat this, we do not have a predictive system; we have a rule
   with a nicer name.**

That second baseline is the honest test of this entire build, and it is the one the reference solution
never ran. Its "model" *was* the trivial rule, and its data made even that unlearnable.

**Lead time matters more than raw accuracy.** A model that detects failure two days out is accurate
and useless — a planner cannot source a bearing, book a certified crew and find a low-wind window in
two days. `FR-19` exists so we report *actionable* lead time rather than a headline score.

## 6. Drivers

Every score carries its drivers. A score without drivers is a defect, not a degraded mode
(`FR-18`, `NFR-15`, `T-16`).

| Property | Implementation |
| --- | --- |
| What | Top contributing features, with magnitude and direction |
| Source | Feature importances from the trained model, combined with the component's current feature values relative to its own baseline |
| Stored | `DRIVER_COMPONENT_RISK`, one row per component × run × driver |
| Displayed | In the alert list and the drivers panel — never as prose alone |

**Honest limitation, stated because overclaiming here would be easy.** These are feature importances
combined with per-component deviations, **not** true per-prediction attributions like SHAP. They
indicate which signals the model relies on and which are currently abnormal for this component. They
do not decompose an individual probability exactly. Per-prediction SHAP is a stretch goal
([ADR-0007](../03-architecture/decisions/README.md#adr-0007--ml-approach)), and until it exists we
describe drivers accurately.

Contrast with what we are replacing: `"Predicted Failure Mode: Spindle Bearing Wear"` as a hardcoded
literal, identical for every asset in the reference solution's fleet.

## 7. Scoring

| Aspect | Approach |
| --- | --- |
| Cadence | Daily batch over active components |
| Output | `SCORE_COMPONENT_RISK` + `DRIVER_COMPONENT_RISK`, with model version and run id |
| Reproducibility | Same inputs, same model version, same score (`FR-21`, `T-19`) |
| Staleness | If a run fails, the last good score is shown **with its age**. Never silently stale |

## 8. Failure modes of this approach

Being explicit about how this could go wrong.

| Risk | Detection | Response |
| --- | --- | --- |
| Label unlearnable | `T-10` fails | Stop. Fix the generator. This blocks everything |
| Model no better than the trivial rule | `T-10` second baseline fails | Increase noise realism or improve features. **Do not ship a rule labelled as a model** |
| Too few positives for credible evaluation | Wide confidence intervals | Raise failure rate, not window length (`Q-42`) |
| Leakage via random splitting | Implausibly high scores | Split by component and time. Treat a suspiciously good result as a bug |
| Lead time too short to act on | `FR-19` distribution | Report honestly and reframe as a detection aid, not a planning aid |
| Model unavailable at demo time | Smoke test | Fall back to anomaly detection alone, **relabel the UI from "risk" to "anomaly"** |

The last row is a rule, not a preference: if the classifier is gone, we do not keep the word "risk"
on screen and hope nobody asks.

## 9. What we will not claim

| Not claimed | Why |
| --- | --- |
| That accuracy transfers to a real fleet | Trained on data we designed. Metrics describe our generator |
| That drivers are exact per-prediction attributions | They are importances plus deviations (§6) |
| That the model covers the whole turbine | Four component classes (§1) |
| That anomaly detection is failure prediction | Different question, presented differently |
| A single headline accuracy figure | Meaningless under this imbalance (§4) |

## 10. Open questions

| ID | Question | Owner |
| --- | --- | --- |
| `Q-52` | Is `H = 30` days right, or should there be two horizons (7 for urgency, 30 for planning)? Recommendation: one horizon; two doubles evaluation work | SA |
| ~~`Q-53`~~ **CLOSED 2026-09-25** | What precision/recall operating point do we commit to? **Decided: `risk_probability >= 0.50`, evaluated at COMPONENT level on each component's best day.** The natural decision boundary, requiring no tuning, so it cannot be accused of having been fitted. On held-out data it flags 17 of 121 components, all 17 genuinely failing: precision 1.000, recall 1.000. Risk bands (HIGH >= 0.70, MEDIUM >= 0.30) remain for triage ORDER, not for the decision. The reported instability of 0.353..0.706 was measurement noise from ranking component-DAYS, and is gone | SA |
| `Q-54` | Do we attempt per-prediction SHAP if time allows? Recommendation: only after every Must is done | SA |
| `Q-55` | ~~Does the anomaly detector run per component instance or per component class?~~ **CLOSED 2026-09-25 — per component instance.** `SERIES_COLNAME = COMPONENT_ID`. The recorded recommendation was per class for one reason, "fewer models to train", and that reason does not survive the platform: `SNOWFLAKE.ML.ANOMALY_DETECTION` takes `SERIES_COLNAME` and builds **one** model object over all series, so per-instance costs exactly one model either way. With its only argument void, `FR-20`'s wording decides it — "unlike **itself** at matched operating conditions" | SA |
