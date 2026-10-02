---
name: alarm-noise-triage
description: "Collapse a raw industrial / IoT / monitoring alarm stream into incidents, classify each as ACTIONABLE, NUISANCE or UNDETERMINED with stored evidence, and report alarm-noise metrics (compression, chattering, standing, flood) in Snowflake SQL — refusing to report compression without the count of real failures suppressed beside it. Triggers: alarm flood, alarm fatigue, nuisance alarms, chattering alarms, alarm rationalisation, ISA-18.2, EEMUA 191, SCADA alarms, alert noise, dedupe alerts, too many alerts."
---

# Alarm noise triage

## Purpose

Operators drown in alarms; most are repeats of a few causes and some are pure nuisance. The
dangerous fix is the one that hides a real failure to make the count look good. This skill builds
deterministic SQL that **earns** the NUISANCE label condition by condition, leaves everything it
cannot assess as UNDETERMINED (never hidden), and reports noise reduction only next to the number
of real failures it would have hidden.

Generalised from `sql/40_engine/01_alarm_incidents.sql` in wind-ops-ai (ADR-0017).

## When to use

- A table of alarm/alert events exists and someone wants to "reduce noise".
- You need numbers for an alarm-management review (ISA-18.2 / EEMUA 191 style).

## Inputs (ask for any that are missing)

| Input | Example |
| --- | --- |
| Alarm table and columns: asset, code, source, severity, raised_at, cleared_at, auto_reset flag | `RAW.FCT_ALARM` |
| Safety-critical codes (never nuisance) | `PROTECTION_TRIP`, `FIRE` |
| Grouping gap: alarms on the same asset+code closer than this are one incident | 10 minutes |
| Optional evidence: an anomaly/risk score per asset per day; a second alarm source | `ML.SCORE`, CMS stream |
| Optional ground truth for the test only: real failure events | `GEN_FAILURE_EVENT` |

## Steps

1. **Incidents.** Gaps-and-islands per `(asset, code)`: a new incident starts when
   `raised_at - lag(cleared_at) > gap`. Keep `n_alarms`, `all_auto_reset`, start/end.
2. **Evidence, one row per incident per channel** (`INCIDENT_EVIDENCE`), each with verdict,
   measured value and reference — so a human can disagree:
   `CORROBORATION` (another source on the asset ±1 day), `RESET_RECURRENCE` (same code back
   within 14 days), `OPERATING_POINT` (reading at matched load vs own baseline), `MODEL` (risk
   **as of the incident date** — never a later score).
3. **Classify, deterministically. No model decides a class.**
   - `ACTIONABLE`: safety-critical, or elevated evidence, or corroborated and not self-clearing.
   - `NUISANCE`: **all** of: chattering (≥3), every trip auto-reset, no recurrence in 14 days,
     no corroboration, not safety-critical, not elevated, monitored, matched-load reading not
     above normal, risk below MEDIUM. Missing evidence fails the condition.
   - `UNDETERMINED`: everything else. Ranked below actionable, never suppressible.
4. **Metrics.** compression = alarms ÷ incidents; chattering = incidents with ≥3 trips in 10 min;
   standing = open > 24 h; flood = 10-min windows with > 10 alarms per operator.
5. **The anti-gaming test.** If ground truth exists: count real failures whose precursor
   incident was classed NUISANCE. It must be **0**. Report it on the same line as compression.

## Outputs

- `INCIDENT`, `INCIDENT_EVIDENCE` tables (or dynamic tables) and a funnel view.
- One summary line: `<alarms> alarms → <incidents> incidents (<x>× compression); <n> nuisance,
  <u> undetermined, <s> safety-critical; real failures hidden: <k>`.

## Limits

- UNDETERMINED will be large when evidence is thin. That is the honest answer; publish the rate.
- Thresholds (gap, 3 trips, 14 days) are starting points from ISA-18.2 practice, not tuned.
- Ground truth is used **only** in the test. Using it inside the classifier makes the test pass
  by cheating.
