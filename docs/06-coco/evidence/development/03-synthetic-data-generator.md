# Development 03 — the synthetic data generator

> **Phase:** Development · **Date:** 2026-09-24/25 · **Author:** SB
> **Story IDs:** `US-2`…`US-7`, `US-52` (and the repair of `US-1`/`US-8`)
> **Tests:** `T-1`, `T-7`, `T-8`, `T-9`, `T-11`, `T-12`, `T-13`, `T-62`, `T-64`…`T-67`
> **Gate:** `G1` — data is worth modelling

Building the six-stage generator behind `G1`, plus the `OPS` assertion suite that proves it.
The session also found that the previous entry's claims about the account were **not true**:
the database it described no longer existed, and the seed script it recorded as run had
never executed successfully.

---

## 1. Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo session ID | `1a36e460-4f53-47db-bfc8-052cc16e89c0` |
| Session title | *Check Snowflake Connection* |
| Workspace hash | `e287939e39ffda63e106c6e52956a6f0` |
| Thread ID | `264562180` |
| Thread account host | `hhwoueb-wq04283.snowflakecomputing.com` |
| Working directory | `/Users/jeevithapandurangaiah/Desktop/Snowflake CoCo/wind-ops-ai` |
| **CoCo account** (where the model ran) | `HHWOUEB-WQ04283`, user `SAPNABHARTI` |
| **Deploy account** (where SQL ran) | `JKDRJBB-MW27072`, locator `EB28292`, user `JVPAN0816` |
| Model | `claude-opus-5` |
| Subagent session | `59f6ece5-f43e-4356-b97f-1f346352a3c9` — *Extract generator story and test specs* (read-only doc extraction) |
| Session file | `~/.snowflake/cortex/conversations/e287939e39ffda63e106c6e52956a6f0/1a36e460-4f53-47db-bfc8-052cc16e89c0.json` (1,012,197 bytes of history) |
| Generator run ID | `RUN-20260924122614` and successors, recorded in `GEN.GEN_RUN_CONFIG` |

**The two accounts are the headline identifier problem, and it is not a typo.** The CoCo
conversation is bound to `HHWOUEB-WQ04283`, while every `snow` CLI deploy went to
`JKDRJBB-MW27072`, because `SNOWFLAKE_DEFAULT_CONNECTION_NAME=jkdrjbb-mw27072`. Token credits
are therefore billed in one account and warehouse credits in the other, and **neither account
alone shows the true cost of this session**. Anyone reconciling these figures must query both.

### SQL to reproduce

CoCo token credits — run in **`HHWOUEB-WQ04283`**:

```sql
select to_varchar(sum(token_credits), '99999.000000') as token_credits,
       sum(tokens)                as tokens,
       count(distinct request_id) as requests,
       min(usage_time)::varchar   as first_seen,
       max(usage_time)::varchar   as last_seen
from SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY
where usage_time >= dateadd(day, -3, current_timestamp())
  and user_name = current_user();
```

Warehouse credits — run in **`JKDRJBB-MW27072`**:

```sql
select warehouse_name, round(sum(credits_used), 4) as credits, count(*) as intervals
from SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
where start_time >= dateadd(day, -3, current_timestamp())
group by 1 order by 2 desc;
```

Measured, 2026-09-25:

| Source | Account | Figure |
| --- | --- | --- |
| `CORTEX_CODE_DESKTOP_USAGE_HISTORY.TOKEN_CREDITS` | `HHWOUEB-WQ04283` | **19.538335** over 180 requests, 41,769,732 tokens, `2026-09-24 18:18:24Z` → `2026-09-25 04:49:18Z` |
| `WAREHOUSE_METERING_HISTORY` — `WOA_BUILD_WH` | `JKDRJBB-MW27072` | **1.5075** |
| `WAREHOUSE_METERING_HISTORY` — all warehouses, 3 days | `JKDRJBB-MW27072` | **1.8746** |

`ACCOUNT_USAGE` lags by up to three hours, so the final runs of the session are **not yet
included** in either figure. Note the column is `TOKEN_CREDITS`, not `CREDITS`.

**The column list is worth recording too**, because the plan's own guidance was wrong about it:
`CORTEX_CODE_DESKTOP_USAGE_HISTORY` has no `INPUT_TOKENS`/`OUTPUT_TOKENS` and no `START_TIME`.
The real columns are `USER_ID`, `USER_NAME`, `USER_TAGS`, `REQUEST_ID`, `PARENT_REQUEST_ID`,
`USAGE_TIME`, `TOKEN_CREDITS`, `TOKENS`, `TOKENS_GRANULAR`, `CREDITS_GRANULAR`, `METADATA`.

## 2. Prompt

Four human turns, verbatim:

1. `check snowflake connection`
2. `understand this project in detail, create new branch, understand how much work is done and
   what is pending? go ahead and complete the development. once done collect the evidence then
   raise the PR`
3. `lets switch to this branch feat/sb/synthetic-data-generator - before you do anything`
   — sent mid-work, while the seed-file bug was being diagnosed
4. `resume now again`

One clarifying question was asked and answered through the question tool: whether the generator
should write into the already-deployed `WIND_OPS_AI_DEV_JP` or a fresh `WIND_OPS_AI_DEV_SB`.
The human chose **`WIND_OPS_AI_DEV_SB`**, so `git config user.initials` was set to `sb` and the
foundation re-deployed.

**Scope was narrowed by CoCo, deliberately and with the reasoning stated up front.** "Complete
the development" spans D6–D15 — ML, engine, agent and app, roughly ten days of four-person work
across 97 stories. CoCo delivered the next gate in full (`G1`) rather than a thin slice of
everything, and said so before starting. See §7.

## 3. What CoCo produced

Thirteen new SQL files, 2,904 lines, plus changes to four existing files.

| File | Lines | Contents |
| --- | --- | --- |
| `sql/10_generate/04_generator_functions.sql` | 232 | `FN_RAND`, `FN_WIND_SPEED`, `FN_EXPECTED_POWER`, `FN_RPM_BAND`, `FN_LOAD_BAND`, `FN_DAMAGE_RATE`, `GEN_SITE_STRESSOR`, `GEN_RUN_CONFIG`, `GEN_FAILURE_EVENT` |
| `sql/10_generate/05_operating_context.sql` | 120 | `SP_GENERATE_OPERATING_CONTEXT` → `GEN_TURBINE_DAY` |
| `sql/10_generate/06_damage_and_failures.sql` | 307 | `SP_GENERATE_DAMAGE` → `GEN_DAMAGE_STATE`, `GEN_FAILURE_EVENT` |
| `sql/10_generate/07_signals.sql` | 259 | `SP_GENERATE_SIGNALS` → `FCT_SIGNAL_10MIN`, incl. seeded historian gaps |
| `sql/10_generate/08_cms_features.sql` | 147 | `SP_GENERATE_CMS_FEATURES` → `FCT_CMS_FEATURE` |
| `sql/10_generate/09_turbine_state.sql` | 142 | `SP_GENERATE_TURBINE_STATE` → `FCT_TURBINE_STATE` |
| `sql/10_generate/10_alarms.sql` | 561 | `SP_GENERATE_ALARMS` — four sources, five seeded patterns, `GEN_CMS_THRESHOLD`, `GEN_SEEDED_PATTERN` |
| `sql/10_generate/11_consequences.sql` | 362 | `SP_GENERATE_CONSEQUENCES` → work orders, part movements, genealogy |
| `sql/10_generate/12_generate_all.sql` | 96 | `SP_GENERATE_ALL` orchestrator |
| `sql/10_generate/20_run_seed.sql` | 22 | parameterised driver for `just seed` |
| `sql/15_quality/01_assertion_framework.sql` | 101 | `OPS.DQ_ASSERTION`, `OPS.DQ_RESULT`, 16 catalogued assertions |
| `sql/15_quality/02_assertions.sql` | 526 | `OPS.SP_RUN_DATA_QUALITY`, `OPS.SP_ASSERT_QUALITY_GATE` |
| `sql/15_quality/10_run_verify.sql` | 29 | driver for `just verify` |

Recipes implemented: **`just seed`** (was a placeholder) and **`just verify`** (was a
placeholder); `just deploy-data` extended from 3 files to 14.

### Data generated in `WIND_OPS_AI_DEV_SB`

| Table | Rows |
| --- | --- |
| `RAW.FCT_SIGNAL_10MIN` | 108,339,384 |
| `RAW.FCT_CMS_FEATURE` | 3,524,000 |
| `RAW.FCT_ALARM_NORMALISED` | ~340,040 |
| `GEN.GEN_DAMAGE_STATE` | 184,000 |
| `RAW.FCT_TURBINE_STATE` | 18,958 |
| `GEN.GEN_TURBINE_DAY` | 18,400 |
| `RAW.FCT_WORK_ORDER` | 452 |
| `GEN.GEN_FAILURE_EVENT` | 58 |

Window: 183 days ending at the generation instant. Runtime: **~4.5 minutes** for the full
generation on an `XSMALL`.

### Assertion results — 16 of 16 pass

| Test | Assertion | Measured |
| --- | --- | --- |
| `T-1` | `DQ-RI-FACTS` | all foreign keys resolve |
| `T-1` | `DQ-ROWCOUNT` | signals with no data: **0 of 4,100** |
| `T-7` | `DQ-WO-PER-FAIL` | 0 of 58 failures lack a corrective work order |
| `T-7` | `DQ-DRIVETRAIN` | drivetrain share **60.3%** |
| `T-8` | `DQ-DEGRADATION` | **58 of 58** failures measured; worst lead-in ratio **1.199**, median 1.916 |
| `T-9` | `DQ-DAMAGE-CORR` | corr(failed, peak damage) **0.5955**; corr(failed, turbine number) **0.0014** |
| `T-11` | `DQ-FRESHNESS` | stalest fact 12h behind the generation instant |
| `T-11` | `DQ-NO-FUTURE` | 0 rows dated in the future |
| `T-12` | `DQ-THRESHOLDS` | 0 thresholds never crossed |
| `T-13` | `DQ-SYNTHETIC` | every row marked synthetic |
| `T-62` | `DQ-ALARM-SCHEMA` | 4 sources present, 0 contract violations |
| `T-64` | `DQ-SEEDED-DIP` | 28 of 28 turbines within **68s**, 0 other sites |
| `T-64` | `DQ-SEEDED-CASCADE` | 16 codes, 1 turbine, 11 minutes |
| `T-65` | `DQ-SEEDED-CHATTER` | **40** auto-reset trips (the planted count); contrast population 19,884 single trips |
| `T-66` | `DQ-SEEDED-STAND` | 1 alarm open 30 days, unacknowledged |
| `T-67` | `DQ-SEEDED-FLOOD` | seeded site **157.5/h** against 12.3/h elsewhere |

`T-8`, `T-11` are gating. `T-10` (learnability) is **not** addressed here — it belongs to the
model layer and remains the D4 decision point.

## 4. What a human changed

**The scope decision was the human's**, twice: the instruction to complete the development, and
the choice of `WIND_OPS_AI_DEV_SB` over the already-deployed `WIND_OPS_AI_DEV_JP` — which cost a
foundation redeploy and made the branch, owner and database agree.

**The branch was renamed mid-session on human instruction** (turn 3), from
`feat/jp/synthetic-data-generator` to `feat/sb/synthetic-data-generator`. CoCo had created the
`jp` branch from `git config user.initials`, which was still set to the previous developer's
initials. The claim row in `STATE.md` §2 was rewritten to `SB` and the stale remote branch
deleted.

Otherwise the human did not rewrite generator logic. The substantive corrections in this session
were CoCo catching its own failures against the assertion suite — which is the point of having
one, and is recorded honestly in §5 rather than presented as first-time success.

## 5. What CoCo got wrong

Thirteen items. The first four were inherited defects CoCo found; the rest were its own.

**Inherited — and they contradict the previous evidence entry.**

1. **The deploy account was empty.** `STATE.md` §5 recorded `WIND_OPS_AI_DEV_KR` with 14 seeded
   dimension tables and 7 fact tables. `JKDRJBB-MW27072` had no `WIND_OPS_AI*` database, no
   `WOA_*` roles and no `WOA_*` warehouses. Everything had to be re-deployed. Caught by running
   `show databases` before trusting the file.
2. **`03_seed_dimensions.sql` had never executed successfully.** It contained a broken
   `INSERT` into `DIM_TURBINE` (an invalid correlated `cross join`) sitting above a
   `-- Fix: simpler approach` rewrite of the same insert. The script aborted at compilation
   before reaching any later statement, so **no dimension could ever have been seeded** — yet
   `development/02` records 100 turbines, 1,000 components and 4,100 signals as seeded. The
   numbers in that entry are correct as *intent* and were reproduced here, but they were not
   observed at the time they were written.
3. **`snow`'s LEGACY templating broke the seed on literal data.** `'C&I'` in `DIM_CONTRACT` was
   parsed as an undefined template variable `&I`, failing template rendering before execution.
   Fixed at the mechanism, not the data — every `snow sql` call is now pinned to
   `--enable-templating STANDARD` — because generated technician notes are deliberately messy
   free text and would have hit this repeatedly.
4. **`FCT_PART_MOVEMENT.STOCK_ID` was `varchar(30)` against a `varchar(60)` key.** A foreign key
   narrower than the primary key it references. Hit on the first real stock id
   (`STK-Chitradurga Site-PT-GBX-BEAR-HSS`, 37 chars).

**CoCo's own errors.**

5. **`T-8` failed on the first serious attempt — 15 of 30 failures showed no trend.** The cause
   was arithmetic, not tuning: at a uniform wear rate a component accrues only ~0.2 of its
   threshold over 183 days, so *which* components fail is decided almost entirely by where they
   started, and any smooth feature of damage moves a few percent across the comparison window.
   **The first fix made it worse.** Making damage accelerate (`dd = (1+Kd)dB`, solved in closed
   form) caused runaway once started: the failure count went to 171, 234, 289 against a target
   of 40–60. That approach was abandoned and the variance moved into the *population* instead —
   a bad batch, `ACCEL_SHARE` of instances degrading 5–11× faster. Final: 58 failures, worst
   lead-in ratio 1.199, all 58 measurable.
6. **Fixing `T-8` broke `T-7`.** A uniform bad-batch rate flattened the failure mix — drivetrain
   share fell from 73% to 46%, with yaw drives and blades failing as often as gearboxes. Fixed
   by scaling batch incidence by each class's wear rate; drivetrain share returned to 60.3%.
7. **One failure was unmeasurable and CoCo nearly declared `T-8` passing anyway.** The run
   reported "57 of 58" with a healthy worst ratio. The earliest failure landed on day 41 of the
   window, so it had no 45–105-day baseline to trend against. Fixed with a 60-day burn-in on
   initial damage, not by relaxing the assertion — a predictive claim about a failure with no
   lead-in data would be dishonest. **The assertion checks the count as well as the ratio
   precisely so this cannot pass quietly.**
8. **Only 9 of each turbine's 41 signals were generated** in the first signal implementation,
   leaving 27 tags per turbine empty — the reference solution's own "51 of 54 sensors with no
   data" defect (`G-1`), reproduced by CoCo while building the thing meant to avoid it. Caught
   by writing the `T-1` row-count assertion. The generator was rewritten to be driven *by*
   `DIM_SIGNAL` using `SIGNAL_TYPE` and the declared normal range, so all 4,100 tags get data
   and a newly added tag cannot become an orphan.
9. **The data-quality alarm source fired on 3,069 of 3,100 turbine-days**, because it compared
   each turbine against the fleet *maximum* — one turbine with a single extra row makes every
   other turbine look short. It also detected nothing real. Replaced with seeded historian gaps
   (12 turbine-days losing their afternoon) plus a median-based rule: 12 alarms, each
   corresponding to an actual gap.
10. **Alarms were dated in the future.** Nuisance events spread across the calendar day and the
    DQ checks stamped 21:00, so on the generation day itself both ran ahead of `NOW` — 1,116
    rows. Caught by `DQ-NO-FUTURE`, which was written for exactly this. Fixed with one guard
    after all inserts rather than a clamp in each.
11. **Grid trips were in the nuisance pool**, putting `SA-GR-001` on six turbines at other sites
    inside the seeded grid-dip window, so the dip no longer looked site-scoped and `T-64`
    failed. Excluded by `severity <> 'TRIP'` — a filter on meaning, not a hand-kept list.
12. **An overstated determinism claim, corrected.** CoCo's `diff` check printed
    "IDENTICAL: generator is deterministic" when the alarm count had in fact moved from 340,038
    to 340,045; the shell comparison silently matched nothing. Re-checked field by field:
    signals, CMS features, failures and work orders are **bit-identical** across runs, and only
    the alarm count moves, because the nuisance stream is clamped to `NOW` and the window end
    advances with wall-clock time. That is required by `T-11`, not a determinism defect — but
    the original claim was wrong as written.

13. **CoCo wrote a flaky test, and it only surfaced on the last run.**
    `DQ-SEEDED-CASCADE` passed at "16 codes within 11 minutes", then failed on a later run at
    **40 minutes with no change to any generator code**. The assertion scoped by
    *(turbine, time window)* rather than by the alarms it had planted, so once the ordinary
    nuisance stream put unrelated alarms on the same turbine inside the window, the test was
    measuring the background instead of the pattern. `DQ-SEEDED-CHATTER` had the same flaw and had
    been quietly reporting **44** trips against 40 planted — passing, but for the wrong reason.
    Both now match on the generator's own `AL-CAS-` / `AL-CHT-` / `AL-DIP-` alarm-id prefixes,
    which is a contract rather than a coincidence. `T-67` deliberately still counts everything,
    because it measures a *rate* and the background is part of the measurement.
    **A test that passes until it doesn't, for reasons unrelated to the change in front of you, is
    worse than no test** — and this one was caught only because `just verify` was re-run a final
    time rather than trusted from the earlier green result. Verified stable across two consecutive
    runs afterwards.

Four Snowflake-specific dead ends, each costing a deploy cycle: `increment` is a reserved word
in scripting; `JOIN LATERAL (SELECT …)` with no `FROM` is an unsupported subquery type; a
correlated `EXISTS` with a `BETWEEN` on the outer timestamp likewise, replaced with a range join
plus `QUALIFY`; and a bare `NUMBER` return column in a procedure's `RETURNS TABLE` makes
`snow` CLI 3.27 fail to parse the result set (`invalid literal for int() with base 10`).

## 6. Cost

| Source | Account | Credits |
| --- | --- | --- |
| CoCo token credits (180 requests, 41.77M tokens) | `HHWOUEB-WQ04283` | **19.5383** |
| Warehouse — `WOA_BUILD_WH` (the generator) | `JKDRJBB-MW27072` | **1.5075** |
| Warehouse — all, 3-day window | `JKDRJBB-MW27072` | 1.8746 |
| **Session total, both sources summed** | — | **≈ 21.05** |

The ratio is again roughly **13:1 in favour of token credits**, consistent with the planning
phase's finding that warehouse metering alone under-reports by about ten times. Generating
108M rows cost about 1.5 credits; talking about generating them cost 19.5.

`ACCOUNT_USAGE` lags up to three hours, so the true total is somewhat higher.

## 7. Traceability

| Field | Value |
| --- | --- |
| Branch | `feat/sb/synthetic-data-generator` (renamed from `feat/jp/…` mid-session) |
| Files added | 13 SQL files, 2,904 lines |
| Files modified | `justfile`, `sql/10_generate/02_fact_tables.sql`, `sql/10_generate/03_seed_dimensions.sql`, `docs/03-architecture/04-code.md`, `docs/03-architecture/deployment.md`, `STATE.md` |
| Gate | `G1` data-quality suite passing, 16/16 |
| Deployed to | `WIND_OPS_AI_DEV_SB` in `JKDRJBB-MW27072` |
| Reproduce | `just deploy-foundation && just deploy-data && just seed && just verify` |

**Deliberately not done, and why.** `T-10` (learnability, the D4 decision point) needs the ML
layer and is untouched — so `G1` is *not* fully passed, because `G1` includes `T-10`. The
curated layer (`US-9`, `US-11`, `US-12`, `US-93`), metric views, engine, agent and app are all
still ahead. The generator was implemented in **set-based SQL rather than the Snowpark
`python/generator/` the code layout anticipates**, because the work is bulk set manipulation
that never needs to leave the warehouse; recorded as a deviation in `STATE.md` §7.

Two documented volume targets were not met and were **not** inflated to look met: alarms reached
~340k against a documented ≈400k, and work orders 452 against ≈1,500. Both are recorded in
`STATE.md` §7 with reasoning rather than padded with rows that correspond to nothing.
