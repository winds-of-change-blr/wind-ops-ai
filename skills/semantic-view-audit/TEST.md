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
| *pending — JP (T-19)* | | | | | | | |
