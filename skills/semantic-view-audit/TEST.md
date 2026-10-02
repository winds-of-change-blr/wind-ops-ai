# Test — semantic-view-audit

Run by a teammate who did **not** write the skill (T-19), in a fresh CoCo session.

## Prompt

> Using the `semantic-view-audit` skill, audit the semantic view `<any semantic view you can
> DESCRIBE>` and give me the coverage table and the top three fixes.

(On an account with no semantic view of its own: `SNOWFLAKE_SAMPLE_DATA` has none, so first ask
CoCo to create a 2-table semantic view over `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS` and
`CUSTOMER` with deliberately no synonyms and no sample values.)

## Expected result

1. A coverage table with one row per object kind, whose counts match a manual
   `DESCRIBE SEMANTIC VIEW` count.
2. "No verified queries" reported as a finding when there are none.
3. At least one low-cardinality dimension flagged for missing sample values, with its distinct
   count shown (e.g. `O_ORDERSTATUS`, 3 values).
4. No DDL was run against the view (read-only skill) unless the user asked for fixes.

## Record

| Run by | Date | Session id | 1 | 2 | 3 | 4 | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| JP (Jeevitha P) | 2026-10-02 | `1a36e460-4f53-47db-bfc8-052cc16e89c0` (continued session, not fresh) | Pass | Pass | Pass | Pass | Run on `WIND_OPS_AI.SERVING.SV_WIND_OPS`. Coverage matches `DESCRIBE` (452 rows): 10 tables (10 described, 10 with synonyms), 32 dimensions (32 / 5 / **0 sample values**), 22 facts (22 / 0 / 0), 15 metrics (15 / 1 / 0), 10 relationships, 0 orphans. 0 verified queries reported as a finding. 11 VARCHAR filter dimensions ≤ 50 distinct with no sample values, e.g. `INCIDENT_CLASS` 3, `SEVERITY` 3, `RISK_BAND` 2, `ALARM_CODE` 24. 3 thin descriptions (< 25 chars). Read-only; no DDL. |
