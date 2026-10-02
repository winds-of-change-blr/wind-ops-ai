# Test — alarm-noise-triage

Run by a teammate who did **not** write the skill (T-19), in a fresh CoCo session.

## Prompt

> Using the `alarm-noise-triage` skill, create a scratch schema `SKILLTEST_<initials>.ALARMS`
> with a synthetic table of 2,000 alarms over 30 days on 10 pumps: one code that chatters and
> always auto-resets, one safety-critical code `HIGH_PRESSURE_TRIP` that also chatters, and
> 3 real failures each preceded by a corroborated alarm. Then triage it and give me the summary
> line.

## Expected result (each must be true)

1. Incidents < alarms, and the summary line is in the skill's format, **including**
   "real failures hidden: N".
2. Every `HIGH_PRESSURE_TRIP` incident is ACTIONABLE, even though it chatters and auto-resets.
3. N = 0: none of the 3 failure precursors is NUISANCE.
4. With no risk-score table supplied, incidents that would otherwise be nuisance are
   UNDETERMINED (missing evidence fails the condition), and the agent says so.
5. `INCIDENT_EVIDENCE` has one row per incident per channel used.

## Record

| Run by | Date | Session id | 1 | 2 | 3 | 4 | 5 | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JP (Jeevitha P) | 2026-10-02 | `1a36e460-4f53-47db-bfc8-052cc16e89c0` (continued session, not fresh) | Pass | Pass | Pass | Pass | Pass | Fixture `SKILLTEST_JP.ALARMS` built to the prompt (2,000 alarms, 10 pumps, 30 days; dropped afterwards). Summary: `2000 alarms → 1490 incidents (1.3× compression); 0 nuisance, 1437 undetermined, 20 safety-critical; real failures hidden: 0`. All 20 `HIGH_PRESSURE_TRIP` incidents ACTIONABLE (80 trips, all auto-reset); 6/6 precursor incidents ACTIONABLE; 150 chattering incidents UNDETERMINED with reason "missing evidence"; 5,960 evidence rows = 1,490 incidents × 4 channels, all unique. |
