# Example — wind-ops-ai, 2026-10-02, account JKDRJBB-MW27072

Synthetic fleet: 100 turbines with alarms, 183 days. Produced by the skill's classification as deployed in
`sql/40_engine/01_alarm_incidents.sql`, read back by the scheduled digest
(`OPS.OPS_DIGEST`, digest `DIG-20261002012748`, built by `WOA_SCHEDULER`):

```json
{ "alarms": 342305, "incidents": 15934, "compression_ratio": 21.5,
  "nuisance": 38, "undetermined": 9655, "safety_critical": 3, "corroborated_real": 7572 }
```

The one-line summary the skill requires:

> 342,305 alarms → 15,934 incidents (21.5× compression); 38 nuisance, 9,655 undetermined,
> 3 safety-critical; real failures hidden: **0** (T-60).

Read it the way a reviewer should:

- **21.5× is grouping, not suppression.** Nothing is hidden by step 1.
- **Only 38 incidents earned NUISANCE.** Nine conditions, all required, is deliberately hard.
- **9,655 UNDETERMINED** — mostly incidents before the anomaly detector had a window. The
  skill refuses to call them nuisance; they stay in the queue.
- **0 real failures hidden** — `DQ-NO-SUPPRESSED-FAILURE` (T-60, gating) in `just verify` joins NUISANCE incidents to the
  synthetic ground-truth failures and must find none.

Evidence for one incident is four rows in `ENGINE.ENG_INCIDENT_EVIDENCE` (CORROBORATION,
OPERATING_POINT, RESET_RECURRENCE, MODEL), each with verdict, measured value and reference.
