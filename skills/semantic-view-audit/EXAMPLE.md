# Example — `WIND_OPS_AI.SERVING.SV_WIND_OPS`, 2026-10-02

Steps 1, 2 and 6 of the skill, run as `WOA_ADMIN` on JKDRJBB-MW27072.

```sql
describe semantic view SERVING.SV_WIND_OPS;
select "object_kind" kind, count(distinct "object_name") n,
       count(distinct iff("property"='COMMENT', "object_name", null)) with_comment,
       count(distinct iff("property"='SAMPLE_VALUES', "object_name", null)) with_samples
  from table(result_scan(last_query_id()))
 where "object_kind" in ('DIMENSION','FACT','METRIC','TABLE','RELATIONSHIP')
 group by 1 order by 1;
```

| Kind | Objects | Described | Synonyms | Sample values |
| --- | --- | --- | --- | --- |
| TABLE | 10 | 10 | 10 | — |
| DIMENSION | 32 | 32 | **5** | **0** |
| FACT | 22 | 22 | 0 | **0** |
| METRIC | 15 | 15 | **1** | — |
| RELATIONSHIP | 10 | — | — | — |

## Findings (real, not fixed yet)

1. **No verified queries.** The view ships none. Highest-impact fix: add the agent suite's
   parity questions as VQRs (open item in STATE.md §3).
2. **0 of 32 dimensions have sample values.** `SEVERITY`, `REGION`, `RISK_BAND`, `SITE_CODE`
   are low-cardinality filter columns; without samples, Analyst guesses the literal.
3. **Synonyms on 5 of 32 dimensions and 1 of 15 metrics.** Operators say "WTG" for turbine and
   "PBA" for contractual availability.
4. **Thin descriptions (< 25 chars):** `SEVERITY` "Alarm severity.", `REGION` "Region of India.",
   `SITE_NAME` "Wind farm name." — no allowed values, no grain.

All 69 dimensions, facts and metrics *are* described — the view passed the original
`DQ-SV-DESCRIBED` and `DQ-SV-SAMPLES-REAL` checks (T-42) and still has the four gaps above, which is the point of
running this audit rather than that check.
