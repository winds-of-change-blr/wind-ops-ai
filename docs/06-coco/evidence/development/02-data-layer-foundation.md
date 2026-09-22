# Development 02 — Data layer foundation: tables, seed data, deploy recipe

> **Phase:** development · **Date:** 2026-09-22 · **Stories:** `US-1`, `US-8` · **Tests:** `T-1` (partial), `T-13`
> **Status:** complete. Foundation deployed, all dimension tables seeded, fact tables created.

## Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo session | Current CoCo CLI session |
| Account | `JKDRJBB-MW27072` (locator `EB28292`) |
| Database deployed to | `WIND_OPS_AI_DEV_KR` |
| Model | `claude-opus-4-6` |

## Prompt

Deploy the foundation infrastructure (roles, warehouses, database, schemas, grants) from the
existing `00_setup` SQL files to `WIND_OPS_AI_DEV_KR`. Then create all dimension and fact tables
per `data-model.md`, populate dimension tables from `company-profile.md`, implement the
`just deploy-data` recipe, and update `STATE.md`.

## What CoCo produced

| Artefact | Path | Lines |
| --- | --- | --- |
| Dimension table DDLs | `sql/10_generate/01_dimension_tables.sql` | 215 |
| Fact table DDLs | `sql/10_generate/02_fact_tables.sql` | 133 |
| Seed dimension data | `sql/10_generate/03_seed_dimensions.sql` | 468 |
| Justfile (updated `deploy-data`) | `justfile` | ~20 lines changed |
| STATE.md | `STATE.md` | §1–§8 updated |
| This evidence entry | `docs/06-coco/evidence/development/02-data-layer-foundation.md` | — |

**Snowflake objects created:**

- 9 roles (`WOA_ADMIN` through `WOA_TECH`), hierarchy and grants applied
- 2 warehouses (`WOA_APP_WH`, `WOA_BUILD_WH`)
- 1 database (`WIND_OPS_AI_DEV_KR`) with 10 schemas
- 14 dimension tables in RAW, all seeded:
  `DIM_COMPONENT_CLASS` (10), `DIM_PLATFORM` (2), `DIM_SITE` (6), `DIM_CONTRACT` (6),
  `DIM_EXCLUSION_CLASS` (5), `DIM_TURBINE` (100), `DIM_COMPONENT` (1000),
  `DIM_COMPONENT_GENEALOGY` (1000), `DIM_SIGNAL` (4100), `DIM_ALARM_CODE` (31),
  `DIM_FAILURE_CODE` (26), `DIM_CREW` (8), `DIM_PART` (19), `DIM_STOCK` (76)
- 6 fact tables in RAW (empty, awaiting generator):
  `FCT_SIGNAL_10MIN`, `FCT_CMS_FEATURE`, `FCT_TURBINE_STATE`,
  `FCT_ALARM_NORMALISED`, `FCT_WORK_ORDER`, `FCT_PART_MOVEMENT`
- 1 generator table in GEN: `GEN_DAMAGE_STATE` (empty)

## What a human changed

Nothing yet — this is the initial deployment from CoCo output.

## What CoCo got wrong

1. **`DIM_STOCK.stock_id` was initially `varchar(30)`**, which was too short for the generated
   stock IDs (`STK-Coimbatore-Central-PT-GBX-BEAR-HSS`). Fixed by altering the column to
   `varchar(60)` and updating the DDL file.

## Cost

| Source | Credits (session estimate) |
| --- | --- |
| CoCo token credits | TBD (ACCOUNT_USAGE lags ~3h) |
| Warehouse credits | Minimal — XSMALL, brief usage for DDL and seed INSERTs |

## Traceability

- Branch: `feat/kr/deploy-data-foundation`
- Commit: pending (this session)
- PR: pending
