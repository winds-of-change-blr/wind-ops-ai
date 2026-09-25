# Development 05 — settling the T-10 margin and the operating point

> **Phase:** Development · **Date:** 2026-09-25 · **Author:** SB
> **Closes:** `Q-60` (the `T-10` margin) and `Q-53` (the precision/recall operating point)
> **Corrects:** [`04-risk-classifier.md`](04-risk-classifier.md) §3 — its tight-budget figures
> **Tests:** `T-10` (gating), new `DQ-STABILITY`

Two open questions delegated to CoCo to decide. Deciding them required first discovering that
**the metric entry 04 used to justify `T-10` was measuring the wrong thing** — twice, in two
different directions.

---

## 1. Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo session ID | `1a36e460-4f53-47db-bfc8-052cc16e89c0` (continuation) |
| Thread ID | `264562180` · workspace `e287939e39ffda63e106c6e52956a6f0` |
| CoCo account | `HHWOUEB-WQ04283`, user `SAPNABHARTI` · Model `claude-opus-5` |
| Deploy account | `JKDRJBB-MW27072` (locator `EB28292`) · database `WIND_OPS_AI_DEV_SB` |
| Evidence of stability | 5 consecutive `MLRUN-*` rows in `OPS.ML_RUN`, metrics in `OPS.ML_METRIC` |

Reproduce the stability claim:

```sql
select metric_scope, metric_name, count(*) runs,
       round(min(metric_value),4) mn, round(median(metric_value),4) med,
       round(max(metric_value),4) mx, round(max(metric_value)-min(metric_value),4) spread
from OPS.ML_METRIC
where metric_name in ('precision_components','recall_components','pr_auc')
  and run_id in (select run_id from OPS.ML_RUN order by trained_at desc limit 5)
group by 1,2 order by 2,1;
```

## 2. Prompt

*"go ahead with Q-60 , Q-53 take your best decision"* — an explicit delegation of two decisions
the previous entry had deliberately left to NK.

## 3. What CoCo produced

### The decisions

**`Q-53` — the operating point. DECIDED: `risk_probability >= 0.50`, at component level, on each
component's best day.** The natural decision boundary, requiring no tuning, so it cannot be
accused of having been fitted to flatter the result. Risk bands (`HIGH >= 0.70`, `MEDIUM >= 0.30`)
stay for triage *order*, not for the decision.

**`Q-60` — the `T-10` margin. DECIDED: three conditions**, all on held-out data at component level:

1. model component precision ≥ **3×** random (the floor)
2. model component recall ≥ the rule's recall (no winning by being shy)
3. model component precision ≥ **1.25×** the rule's (the honest test)

1.25× was chosen because it is a margin a maintenance manager would recognise — a quarter fewer
wasted truck rolls at equal detection — and because it is deliberately **not** set just below the
observed value, which would be reverse-engineering the pass mark from the answer. Condition 2
exists because precision alone is gameable: a model that flags one certain component scores 1.000
precision and is useless.

### The corrected comparison

Held-out: 121 components, 17 failing. Each method at its own operating point:

| | Components flagged | Truly failing | Precision | Recall |
| --- | --- | --- | --- | --- |
| **Model** (`p >= 0.50`) | 17 | 17 | **1.000** | **1.000** |
| **Trivial rule** (per-class p95) | 29 | 17 | 0.586 | 1.000 |
| Stratified random | — | — | 0.140 | — |

**`T-10` passes at 1.71× against a 1.25× bar.** Both methods find every failing component; the
model does it with zero false positives while the rule sends crews to 12 healthy ones.

The budget sweep, now recorded in `OPS.ML_METRIC` so a reader can see where the comparison does
and does not discriminate:

| Budget K | Model finds | Rule finds |
| --- | --- | --- |
| 5 | 5 | 5 |
| 8 | 8 | 8 |
| 12 | 12 | 9 |
| 17 | **17** | 10 |
| 25 | 17 | 10 |
| 34 | 17 | 10 |

Below K=8 both are saturated and the comparison is meaningless. Ranked by band-energy magnitude
the rule **plateaus at 10 of 17** and never reaches the other 7 at any budget.

### Code

| File | Change |
| --- | --- |
| `sql/25_ml/03_evaluate.sql` | tight-budget block replaced with the operating-point comparison + the recorded sweep |
| `sql/15_quality/03_ml_assertions.sql` | `T-10` rewritten to the three decided conditions; new `DQ-STABILITY` |
| `docs/05-ai-ml/ml-models.md` §10 | `Q-53` closed |
| `docs/07-quality/testing-and-validation.md` | `Q-60` closed |
| `docs/08-delivery/raid-log.md` | both closed |
| `docs/06-coco/evidence/development/04-risk-classifier.md` | superseded-in-part marker |

## 4. What a human changed

Nothing. The human delegated both decisions explicitly. The substantive work was CoCo finding
that its own previous justification was unsound and correcting it unprompted — recorded in §5
rather than quietly replaced.

## 5. What CoCo got wrong

**The headline claim in entry 04 was wrong, and it was CoCo's own metric that was wrong — twice,
flattering a different side each time.**

1. **Ranking component-DAYS.** The first tight-budget metric took the top N of 18,333
   component-days. Most of the budget went on repeat days of the same asset, and the top of the
   ranking is crowded with near-1.0 probabilities so ties broke arbitrarily. **This was the whole
   of `Q-53`'s reported 0.353–0.706 instability — measurement noise, not model noise.** Entry 04
   reported that range as a property of the model. It was not.
2. **Then, over-correcting, ranking only the rule's own shortlist.** Switching to component-level
   ranking, CoCo restricted the rule's candidate pool to components it had already flagged and
   ranked within that. This reported recall 1.000 for the rule and *hid the false positives that
   are precisely its weakness* — the opposite bias to defect 1.
3. **A fleet-wide percentile instead of per-class.** A mid-investigation query thresholded band
   energy globally rather than per monitored point. That scored the rule materially worse
   (recall 0.588 instead of 1.000) and would have handed the model an easy win. The registered
   rule says "the 95th percentile for that monitored point", so the per-class reading is the
   faithful one and is what the final comparison uses. **Using the weaker reading would have been
   exactly the strawman `A-20` warns about**, and it was caught only by re-reading the
   pre-registered spec rather than trusting the query.

So entry 04's *"model 0.353–0.706 vs rule 0.000 — categorical"* was an artifact. The real result
is narrower and more defensible: **the same detection, with 41% fewer components sent for
inspection.** `T-10` passes either way, but the claim we are entitled to make is different, and
the deck must say the correct one.

**What this cost and what stopped it.** Three flawed metrics survived because each *looked*
plausible and pointed the way we wanted. What caught them was sweeping the budget instead of
trusting one operating point, and re-reading the pre-registered baseline spec. `DQ-STABILITY` now
fails the build if the headline moves more than 0.05 across five retrainings, so a lucky run
cannot be quoted again.

**Still not fixed, and now visible.** The model is very strong on this dataset (precision 1.000,
PR-AUC 0.988). `ml-models.md` §8 says to treat a suspiciously good result as a bug. There is no
leakage — features are observable-only, the split is component-disjoint, `DQ-NO-ID-FEATURE`
passes — so the honest reading is that **the generator's damage→feature mapping is too clean**:
the CMS cubic term makes band energy nearly determine failure. `ADR-0006`'s honesty constraint
anticipates exactly this and prescribes more noise. The remedy belongs to the generator, is not
attempted here, and is recorded in `STATE.md` §7.

## 6. Cost

Incremental over entry 04, same two-day `ACCOUNT_USAGE` window: five extra train/evaluate cycles
plus two full `just deploy-ml` runs. Warehouse cost is negligible (≈0.1 credits; each cycle is
seconds on an `XSMALL`); the reasoning to find three metric defects is the expensive part.
Cumulative session totals remain as reported in `STATE.md` §6 — both credit sources summed.

## 7. Traceability

| Field | Value |
| --- | --- |
| Branch | `feat/sb/deploy-ml` (extends PR #6) |
| Gate | `just deploy-ml` green twice, **8 ML assertions**, 0 failures; `just verify` green across both suites |
| Decisions closed | `Q-60`, `Q-53` — in the docs, not only in code |
| Reproduce | `just deploy-ml` |

**Deliberately not done.** The anomaly detector (`US-22`, `T-18`) is still missing, so `G2` is
**not passed**. Raising the generator's noise to erode the model's near-perfect score is a
generator change and belongs with `G1`'s owner, not smuggled into an ML PR.
