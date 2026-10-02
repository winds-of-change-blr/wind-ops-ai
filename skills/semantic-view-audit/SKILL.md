---
name: semantic-view-audit
description: "Audit a Snowflake semantic view before Cortex Analyst or a Cortex Agent relies on it: coverage of descriptions, synonyms and sample_values per dimension/fact/metric, thin or unit-less descriptions, relationships, and whether verified queries exist — then check that described sample values actually occur in the data. Produces a scored findings table and a fix list. Triggers: audit semantic view, semantic view quality, Cortex Analyst accuracy, why is analyst wrong, check semantic model, sample values, synonyms, verified queries coverage."
---

# Semantic view audit

## Purpose

Cortex Analyst answers only as well as its semantic view describes the data. The defects that
cost accuracy are boring and findable: a dimension with no synonyms, a description with no unit
or grain, sample values that are absent (so the model guesses literals), no verified queries.
This skill measures them from `DESCRIBE SEMANTIC VIEW` — read-only, any account.

## Inputs

| Input | Example |
| --- | --- |
| Semantic view FQN | `WIND_OPS_AI.SERVING.SV_WIND_OPS` |
| A role that can DESCRIBE it and SELECT its base tables | `WOA_ADMIN` |
| Optional: the source YAML/SQL, to propose fixes in place | `sql/30_serve/02_semantic_view.sql` |

## Steps

1. `DESCRIBE SEMANTIC VIEW <fqn>;` then over `result_scan(last_query_id())` aggregate per
   `object_kind`: objects, with `COMMENT`, with `SYNONYMS`, with `SAMPLE_VALUES`.
2. **Thin descriptions:** `COMMENT` shorter than 25 characters, or a FACT/METRIC whose comment
   names no unit (`INR`, `MWh`, `%`, `days`, `count`...) or no grain ("per turbine-day").
3. **Low-cardinality dimensions with no sample values:** for each VARCHAR dimension, `select
   count(distinct <expr>)` on its base table; ≤ 50 distinct and no `SAMPLE_VALUES` is a finding —
   Analyst will otherwise invent literals in `WHERE`.
4. **Sample values that do not exist:** for each declared sample value, check it occurs in the
   base column. A sample value not in the data is worse than none.
5. **Relationships:** every logical table except the fact should be reachable; list orphans.
6. **Verified queries:** count them (in the YAML, or `SHOW VERIFIED QUERIES` where available).
   Zero is a finding, not a pass.
7. Report the table below and a fix list ordered by expected accuracy impact:
   verified queries → sample values on filter dimensions → synonyms → thin descriptions.

## Output

| Kind | Objects | Described | Synonyms | Sample values |
| --- | --- | --- | --- | --- |

plus findings, each with the object, the defect and the proposed text.

## Limits

- It measures the view, not answers. Pair it with a parity check (same metric through Analyst,
  the view and the app) to measure answers.
- Unit/grain detection is a keyword heuristic; read the flagged ones.
