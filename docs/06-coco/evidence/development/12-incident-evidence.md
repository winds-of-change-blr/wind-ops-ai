# Development 12 — incident evidence and the `UNDETERMINED` queue

> **Gates:** `G4`, action is safe (the alarm-intelligence half) · **Date:** 2026-09-26 · **By:** JP with CoCo
> **Account:** `JKDRJBB-MW27072` · **Database:** `WIND_OPS_AI_DEV_SB` · **Branch:** `feat/jp/incident-evidence`

## 1. Verifiable identifiers

| What | Identifier |
| --- | --- |
| CoCo session | `1a36e460-4f53-47db-bfc8-052cc16e89c0` |
| Stack under test | `main` `1989395` (PR #14), rebuilt from the recipes onto `WIND_OPS_AI_DEV_SB`, then `deploy-engine → deploy-action → deploy-app → verify` |
| Engine run | `343349 alarms -> 15937 incidents -> 6400 actionable, 9504 undetermined, 33 nuisance. Compression 21.6:1, real failures suppressed 0, undetermined rate 0.5963` |
| Evidence rows | `ENGINE.ENG_INCIDENT_EVIDENCE`: **63,748**, which is exactly 15,937 × 4 channels |
| Operator queue | `ENGINE.ENG_OPERATOR_QUEUE`: **15,904** = 6,400 actionable + 9,504 undetermined |
| Gate runs | `DQ-20260926105902` (engine), `DQ-20260926105947` (action) and the final `just verify`: **72/72**, 29 gating |
| New assertions | `DQ-T68-EVIDENCE-COVERAGE`, `DQ-T68-EVIDENCE-WELLFORMED`, `DQ-T68-EVIDENCE-CONSISTENT`, `DQ-T61-UNDETERMINED-QUEUED`, `DQ-T61-RATE-PUBLISHED`, `DQ-T61-NEVER-SUPPRESSED` (all six gating), plus `DQ-I19-RISK-AGREES` |
| `I-19` incidents, now `UNDETERMINED` | `MH-STR-T08\|SA-OT-003\|20260925122100`, `MH-STR-T08\|SA-PT-001\|20260919181900` |

## 2. Prompt

> *"As per the plan, what is the next thing"* → *"Let's do it"*, accepting: land the scorer fix,
> claim D10 in `STATE.md`, then build `T-61` and `T-68` on `feat/jp/incident-evidence`.

D10 in [`project-plan.md`](../../../08-delivery/project-plan.md) is *"Alarm classification +
`UNDETERMINED` + evidence rows"*, proved by `T-68`, `T-61` and `T-31`. `T-31` was already done (NK,
evidence 11). The other two were gating tests with no assertion.

## 3. What CoCo produced

**The gap was bigger than missing rows.** [`ADR-0017`](../../../03-architecture/decisions/adr-0017-alarm-classification.md)
names four evidence channels. Before this change the engine weighed:

| Channel (ADR-0017) | Before | After |
| --- | --- | --- |
| Another channel agrees at matched operating conditions | Another alarm source on the turbine within ±1 day, as a boolean | Same rule, **stored** with its verdict |
| Load or RPM already explains the reading | **Not computed** | The component's primary CMS reading **at matched load** (HIGH/FULL, `25_ml/01_features.sql:127`) against its own baseline. Above the class p95 means load does not explain it |
| Auto-reset and never recurred | `all_auto_reset`, `recurs_14d` | Same, **stored** |
| The component's risk score | A proxy: an anomaly flag within 3 days or a CMS alarm within 7 | The proxy, **plus the classifier's risk on the incident date** from that date's features, **plus the highest risk anywhere on the turbine** from a score dated on or before the incident (`I-19`). Never a later score |

The following were produced:

- **`ENGINE.ENG_INCIDENT_EVIDENCE`**: one row per incident per channel, holding the verdict
  (`SUPPORTS_ACTIONABLE` / `SUPPORTS_NUISANCE` / `NO_EVIDENCE`), the measured value, the reference
  it was compared to, the as-of date and a sentence. It is written by `SP_BUILD_INCIDENTS` **from
  the same temp table the classification reads**, so the stored evidence cannot drift from the
  decision it explains.
- **Three new guards on `NUISANCE`.** A reading that is above normal at matched load blocks it,
  and so does the component's risk ≥ 0.30 on the day. So does MEDIUM/HIGH risk anywhere on the
  turbine from an earlier score (`I-19`), and so does a *missing* matched-load reading (§5). Every
  new input can only make `NUISANCE` harder to earn, which is why `T-60` cannot regress because
  of them.
- **`ENGINE.ENG_OPERATOR_QUEUE`**: one queue with every `ACTIONABLE` incident then every
  `UNDETERMINED` one, carrying `queue_rank` and `queue_total`.
- **The app's *Alarms* tab** reads that queue instead of a class filter. It shows **"Showing 200 of
  15,902"** instead of truncating silently, and a *Why was it classed this way?* panel lists the four
  evidence rows for the chosen incident.
- **Six gating assertions.** `T-68` coverage is an anti-join of incidents × 4 channels, plus
  well-formedness, plus consistency (no `NUISANCE` incident carries any non-nuisance verdict).
  `T-61` checks that the queue is complete and ordered, that the rate reconciles, and that no
  `UNDETERMINED` incident is under an active suppression.

**Every new check was shown to fail.** A check that has never failed proves nothing, so each one was
mutation-tested against the live data:

| Mutation | Check | Result |
| --- | --- | --- |
| Delete one `MODEL` evidence row (in a transaction, rolled back) | coverage | caught **1** |
| Set one verdict to `'MAYBE'` (rolled back) | well-formed | caught **1** |
| Give one `NUISANCE` incident a `SUPPORTS_ACTIONABLE` row (rolled back) | consistent | caught **1** |
| Redefine the queue view to drop undetermined incidents with no component, then run the real `SP_RUN_ENGINE_QUALITY` | `DQ-T61-UNDETERMINED-QUEUED` | **FAILED**: *"1121 of 9502 UNDETERMINED incidents missing"*. The view was restored from source and `verify` re-run clean |
| Run `DQ-I19-RISK-AGREES`'s query against the classification **before** the `I-19` fix | `DQ-I19-RISK-AGREES` | found **2**, exactly the two `MH-STR-T08` incidents. After the fix: 0 |

After the rollback there were 63,748 evidence rows, unchanged.

## 4. What a human changed

Nothing in the code. JP directed the order of work (scorer fix first, then claim, then build) and
accepted the plan as proposed.

## 5. What CoCo got wrong

| Error | Caught by | Fix |
| --- | --- | --- |
| **The claim cited `FR-70`.** The requirements are `FR-63` (classification with stored evidence) and `FR-64` (the `UNDETERMINED` policy) | Reading `requirements.md` after writing the claim | Corrected in `STATE.md` §2 |
| **`DQ-T61-NEVER-SUPPRESSED` was first written into the engine suite.** It reads `ACTION.ACT_V_SUPPRESSION_ACTIVE`, and `deploy-engine`'s gate runs before `deploy-action` creates it. It would have passed on this redeploy and **failed on every clean build** (`T-52`) | Reviewing the recipe order before deploying | Moved to `06_action_assertions.sql`, which runs after `ACTION` exists |
| **App code indexed `queue["QUEUE_TOTAL"]`.** `_run` lowercases every column, so the tab would have raised `KeyError` on load | Reading `_run` before deploying | Lowercase keys |
| **The rule accepted `NUISANCE` with no matched-load reading, while `DQ-T68-EVIDENCE-CONSISTENT` rejected the same incident.** It passed only because all 35 happened to have a reading, so it was one data change away from a gate failure | Asking *why* the new guards blocked nothing (below) | A missing reading now blocks `NUISANCE` too. Absence of evidence is not health, as this file's own header already says |
| **The first `T-61` mutation tested nothing.** Relabelling an incident's class does not exercise the failure the check exists for, which is the queue view dropping undetermined incidents | Re-reading what the check guards | Broke the view itself and ran the real procedure (§3) |
| **The point-in-time risk guard missed `I-19`.** It checked the incident's *own* component, but `FR-32`'s suppression guard is turbine-level. Two nuisance trips on `MH-STR-T08` (GEN and PIT, both ~0.000001 risk) sat on a turbine whose other component was scored **HIGH** (0.99999). `DQ-T29-RISK` would still have refused the suppression, but the classification disagreed with the guard | Updating `STATE.md` §3, which listed `I-19` as open | A turbine-level guard, using only scores dated on or before the incident, plus `DQ-I19-RISK-AGREES`, read straight from the scores so it shares no derivation with the evidence rows |

**The honest result on the new guards:** the two component-level guards (matched load, risk on the
day) blocked **0 of the 35** incidents the old rule called nuisance. All 35 read normal at matched
load and scored under 0.30 on the day. The turbine-level guard (`I-19`) blocked **2**, so nuisance
went from 35 to 33 and those two are now `UNDETERMINED`. Real failures suppressed stayed at **0**
throughout. So the headline barely moves. The value of this change is that every classification can
now be checked, and that the classification now agrees with the suppression guard. That is recorded
in the SQL header too, so nobody later reads the guards as having improved `T-60`.

## 6. Cost

| Source | Credits |
| --- | --- |
| Warehouse on `JKDRJBB-MW27072` (`WAREHOUSE_METERING_HISTORY`, 2026-09-26, whole day, including the morning's full rebuild) | **2.89** |
| CoCo tokens on `JKDRJBB-MW27072` (`CORTEX_CODE_DESKTOP_USAGE_HISTORY`, 2026-09-26, 95 requests) | **7.79** |
| **Total on `JKDRJBB`** | **≈ 10.7** |

Metering lags by a few hours, so these are lower bounds. Earlier turns of this session billed
to `HHWOUEB-WQ04283` (`R-31`). **None of this is on the team's `BGTCHIX` $400 budget.**

## 7. Traceability

| Requirement | Test | Assertion | Where |
| --- | --- | --- | --- |
| `FR-63`: classify, storing the evidence weighed | `T-68` | `DQ-T68-EVIDENCE-COVERAGE`, `-WELLFORMED`, `-CONSISTENT` | `sql/40_engine/01_alarm_incidents.sql`, `sql/15_quality/04_engine_assertions.sql` |
| `FR-64`: `UNDETERMINED` stays in the queue, below actionable, never hidden, rate published | `T-61` | `DQ-T61-UNDETERMINED-QUEUED`, `-RATE-PUBLISHED` (engine suite), `-NEVER-SUPPRESSED` (action suite) | the same, plus `sql/15_quality/06_action_assertions.sql` and `app/streamlit_app.py` |
| `FR-32`: no real failure hidden | `T-60` | `DQ-NO-SUPPRESSED-FAILURE`: still 0 | unchanged |
| `FR-32`: the classification agrees with the suppression guard (`I-19`) | `T-29` | `DQ-I19-RISK-AGREES` | `sql/15_quality/04_engine_assertions.sql` |

**Not proven here:** the app change was deployed (`deploy-app` succeeded and confirmed the warehouse
runtime), but the *Alarms* tab was **not exercised in a browser**. The SQL behind it is covered by the
assertions; the rendering is not.
