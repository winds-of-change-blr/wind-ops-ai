# Run `just` to list commands, grouped. Requires: uv, just.
#
# Every deployment to Snowflake goes through a recipe in the `snowflake` group.
# Never run ad-hoc DDL against a shared database — see AGENTS.md > Deployment.

set unstable := true

# --- variables ---------------------------------------------------------------

# There is ONE database, WIND_OPS_AI, on the team account JKDRJBB-MW27072, and
# every developer deploys to it (AGENTS.md > Deployment). There are no personal
# clones and no per-user suffix: `_resolve-db` refuses any other account.
team_account := "JKDRJBB-MW27072"

# The Snowflake connection. `snow` picks up SNOWFLAKE_DEFAULT_CONNECTION_NAME from
# the environment on its own, so recipes below deliberately do NOT pass
# --connection: whatever `snow connection test` uses is what a deploy will use, and
# there is only ever one answer. This variable exists so `just target` can show it.
connection := env_var_or_default("SNOWFLAKE_DEFAULT_CONNECTION_NAME", "(snow default)")

# The one target database. `_resolve-db` is what REFUSES the wrong account; any
# recipe that touches Snowflake must depend on it so the guard runs first.
database := "WIND_OPS_AI"

# Where the numbered deployment SQL lives.
sql_dir := "sql"

# How every recipe below invokes `snow sql`.
#
# `--enable-templating STANDARD` restricts variable substitution to the `<% ... %>`
# syntax we actually use. The CLI default is `LEGACY,STANDARD`, and LEGACY also
# treats bare `&IDENT` as a variable — so a literal ampersand in *data* becomes a
# template error: `'C&I'` in DIM_CONTRACT rendered as undefined variable `&I` and
# aborted the whole seed. Generated technician notes (see
# docs/04-data/data-sources-and-synthetic-data.md §5) are deliberately messy free
# text, so this would have kept recurring. STANDARD only, everywhere.
snow_sql := "snow sql --enable-templating STANDARD"

# Project board this repo's PRs are tracked on, and its Iteration field id
# (`gh project field-list 1 --owner winds-of-change-blr` to re-derive if the
# board is ever recreated).
project_owner := "winds-of-change-blr"
project_number := "1"
project_title := "Snowflake COCO CLI GCC 2026"
iteration_field_id := "PVTIF_lADOE5mWsc4BjYhOzhiNAXI"

# Show available commands
[group('help')]
default:
    @just --list --list-heading $'\nwind-ops-ai — recipes by group:\n'

# Print the resolved deployment target and connection, and nothing else.
# Run this before any deploy. If it is not what you expect, stop.
[doc('Print the resolved deployment target and connection. Run before any deploy')]
[group('snowflake')]
target: _resolve-db
    @printf 'connection : %s\n' "{{connection}}"

# --- session -----------------------------------------------------------------

# Start-of-session handoff: current state, branch, recent work, open PRs.
# Run this FIRST, every session. See AGENTS.md > Session protocol.
[doc('Start-of-session handoff: state, branch, recent work, open PRs. Run FIRST')]
[group('session')]
state:
    #!/usr/bin/env bash
    set -uo pipefail
    cat STATE.md
    printf '\n===============================================================\n'
    printf 'branch: %s\n\n' "$(git symbolic-ref --quiet --short HEAD || echo HEAD)"
    printf 'recent commits:\n'
    git --no-pager log --oneline -10
    printf '\nuncommitted:\n'
    git status --short || true
    printf '\nopen PRs:\n'
    gh pr list --limit 10 2>/dev/null || echo '  (gh unavailable)'
    printf '\nReminder: claim your work in STATE.md section 2 before you start.\n'

# --- setup -------------------------------------------------------------------

# Create venv, install all deps, install git hooks
[group('setup')]
bootstrap:
    uv sync
    uv run pre-commit install

# Install / update dependencies from pyproject.toml
[group('setup')]
sync:
    uv sync

# --- dev ---------------------------------------------------------------------

# Auto-format the codebase
[group('dev')]
fmt:
    uv run ruff format .
    uv run ruff check --fix .

# Lint (ruff). Use `just fmt` to auto-fix.
[group('dev')]
lint:
    uv run ruff check .
    uv run ruff format --check .

# Run the test suite
[group('dev')]
test *ARGS:
    uv run pytest {{ARGS}}

# Lint + test (the full local gate)
[group('dev')]
check: lint test

# Run all pre-commit hooks against all files
[group('dev')]
hooks:
    uv run pre-commit run --all-files

# --- snowflake ---------------------------------------------------------------
#
# PLACEHOLDERS. Every recipe below exits 1 until it is implemented, on purpose:
# a deploy command that silently succeeds without deploying is worse than one
# that is missing. Each names the plan item that will implement it.
#
# Three rules every one of these must satisfy when implemented:
#   1. Idempotent. Safe to run twice. CREATE OR ALTER / IF NOT EXISTS, never
#      "drop then create" on anything holding data.
#   2. Prints its target first; `_resolve-db` refuses any account but the team's.
#   3. No statement may fail unnoticed. Originally written as "one statement per
#      call", on the belief that batched multi-statement SQL silently skips
#      statements. That is NOT reproducible on snow CLI 3.27: `snow sql -f` echoes
#      every statement, aborts at the first failure, and exits non-zero. So
#      grouped .sql files are fine and are what we use. Verified by execution;
#      recorded in STATE.md §7.

# Full stack into the resolved target, in dependency order. Idempotent.
# Implements: US-44 (deployment scripts) · docs/03-architecture/deployment.md
[doc('Deploy the full stack into the resolved target, in dependency order')]
[group('snowflake')]
deploy: _resolve-db
    #!/usr/bin/env bash
    # The whole stack, in dependency order, then every gate. Each step is its
    # own recipe and gates itself, so the first failure stops the chain with the
    # failing gate on screen. T-52 runs this twice into a clean database.
    set -euo pipefail
    j="just"
    for step in deploy-foundation deploy-data seed deploy-ml deploy-engine deploy-agent deploy-action deploy-app verify; do
        printf '\n\n##### %s #####\n' "$step"
        $j "$step"
    done
    printf '\nfull deploy + verify complete in %s.\n' "{{database}}"

# Roles, warehouses, database, schemas, grants. Run once per environment.
# Naming authority: docs/03-architecture/04-code.md. Least privilege (NFR-3).
#
# IMPLEMENTED (US-44, US-45, NFR-3, NFR-6 — proven by T-50, T-52).
# Two stages, per docs/03-architecture/deployment.md §3:
#   0x  elevated, one-time, account objects only (roles, warehouses, database)
#   1x  WOA_ADMIN — schemas and grants; holds no account-level privilege
# There is no developer-clone grant step any more: one team database, built
# only through these recipes as WOA_ADMIN.
[doc('Roles, warehouses, database, schemas, grants. Once per environment')]
[group('snowflake')]
deploy-foundation: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n\n' "{{connection}}"

    for f in 01_account_roles 02_account_warehouses 03_account_database \
             10_schemas 11_grants; do
        printf '\n=== %s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/00_setup/${f}.sql" -D "database={{database}}"
    done

    printf '\nfoundation deployed into %s. Run `just verify`.\n' "{{database}}"

# GEN/RAW/CURATED/SERVING: generator, tables, dynamic table (M12), semantic view.
# Implements: US-8..US-12 (generator) · US-18..US-22 · US-93 (incremental path)
#
# IMPLEMENTED for the generator (US-1..US-8, US-52) and the OPS data-quality
# suite. The curated layer (20_curate), metric views (30_serve) and the
# incremental dynamic table (US-93) are still to come.
#
# This deploys the CODE. It writes no fact rows — run `just seed` for that, then
# `just verify`. Keeping the two apart is what lets `just update` re-apply a
# changed procedure without touching 108M rows of generated data.
[doc('GEN/RAW/CURATED/SERVING: generator, tables, dynamic table, semantic view')]
[group('snowflake')]
deploy-data: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n' "{{connection}}"

    # Order is a dependency order, not a preference: the functions must exist
    # before the procedures that call them, and 12_generate_all calls all of them.
    for f in 01_dimension_tables 02_fact_tables 03_seed_dimensions \
             04_generator_functions 05_operating_context 06_damage_and_failures \
             07_signals 08_cms_features 09_turbine_state 10_alarms \
             11_consequences 13_underperformance 14_planning_context 12_generate_all; do
        printf '\n=== 10_generate/%s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/10_generate/${f}.sql" -D "database={{database}}"
    done

    for f in 01_assertion_framework 02_assertions; do
        printf '\n=== 15_quality/%s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/15_quality/${f}.sql" -D "database={{database}}"
    done

    printf '\ndata layer deployed into %s. Run `just seed`, then `just verify`.\n' "{{database}}"

# ML schema: train, evaluate, register. Writes metrics to OPS for T-15/T-17.
# Must fail loudly if the model does not beat both baselines (T-10).
#
# IMPLEMENTED (US-18..US-21, T-10, T-14..T-17, T-19).
#
# Deploys the ML code, then runs features -> train -> evaluate -> score IN THAT
# ORDER, then gates on the ML assertions. The order is not cosmetic: retraining
# without re-evaluating leaves the newest model with no recorded metrics, which
# makes T-10 unevaluable and T-87 unsatisfiable.
#
# The gate is OPS.SP_ASSERT_QUALITY_GATE, which RAISEs, so this recipe exits
# non-zero if the model fails to beat BOTH pre-registered baselines. That is the
# contract: ml-models.md §8 says "do not ship a rule labelled as a model", and a
# deploy step that prints a failure and then succeeds would let us do exactly that.
[doc('ML schema: train, evaluate, register. Fails if baselines are not beaten')]
[group('snowflake')]
deploy-ml horizon="30": _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n' "{{connection}}"
    printf 'horizon    : %s days\n\n' "{{horizon}}"

    for f in 00_baseline_spec 01_features 02_train 03_evaluate 04_score_and_drivers 05_anomaly; do
        printf '\n=== 25_ml/%s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/25_ml/${f}.sql" -D "database={{database}}"
    done

    printf '\n=== 15_quality/03_ml_assertions ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/03_ml_assertions.sql" -D "database={{database}}"

    printf '\n=== run: features -> train -> evaluate -> score ===\n'
    {{snow_sql}} -f "{{sql_dir}}/25_ml/10_run_ml.sql" \
        -D "database={{database}}" -D "horizon_days={{horizon}}"

    printf '\n=== gate on the ML assertions (T-10 is gating) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/11_run_verify_ml.sql" -D "database={{database}}"

    printf '\nML layer deployed and gated in %s.\n' "{{database}}"

# ENGINE/ACTION: correlator, ranking, guards, approval-gated writes, audit.
# Nothing here may grant an agent a write tool (AGENTS.md rule 2).
[doc('ENGINE/ACTION: correlator, ranking, guards, approval-gated writes, audit')]
[group('snowflake')]
deploy-engine: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n\n' "{{connection}}"

    # Serving views first: ENG_ALERT_RANKED reads MET_AVAILABILITY_CONTRACTUAL.
    for f in 30_serve/01_metrics 40_engine/01_alarm_incidents 40_engine/02_alert_ranked 30_serve/03_energy_and_oee 40_engine/03_window_candidates 40_engine/04_suggestions 15_quality/04_engine_assertions; do
        printf '\n=== %s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/${f}.sql" -D "database={{database}}"
    done

    # 108M signal rows -> ~18k turbine-days, once, so OEE is not recomputed per page.
    printf '\n=== build turbine-day energy (OEE, lost energy) ===\n'
    printf 'use role WOA_ADMIN;\nuse database %s;\nuse warehouse WOA_BUILD_WH;\ncall SERVING.SP_BUILD_TURBINE_DAY();\n' "{{database}}" \
        | {{snow_sql}} --stdin

    # Window engine (CMP-9) then suggestions (ADR-0018): candidates first, because
    # suggestions may only select from them (T-71).
    printf '\n=== build window candidates and schedule suggestions ===\n'
    printf 'use role WOA_ADMIN;\nuse database %s;\nuse warehouse WOA_BUILD_WH;\ncall ENGINE.SP_BUILD_WINDOW_CANDIDATES();\ncall ENGINE.SP_BUILD_SUGGESTIONS();\n' "{{database}}" \
        | {{snow_sql}} --stdin

    printf '\n=== build incidents ===\n'
    printf 'use role WOA_ADMIN;\nuse database %s;\nuse warehouse WOA_BUILD_WH;\ncall ENGINE.SP_BUILD_INCIDENTS();\n' "{{database}}" \
        | {{snow_sql}} --stdin

    printf '\n=== gate on the engine assertions (T-60 is gating) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/12_run_verify_engine.sql" -D "database={{database}}"

    printf '\nserving + engine deployed and gated in %s.\n' "{{database}}"

# DOCS + agent (G3): semantic view, maintenance documents, search, agent.
# Implements: US-27..US-32 · gated by 15_quality/13_run_verify_g3 (T-48 gating)
#
# Order matters: the agent's tools point at the semantic view and the search
# service, so both must exist first. Documents are regenerated from
# scripts/generate_maintenance_docs.py every time, never hand-edited.
# Read-only tools only (AGENTS.md rule 2); DQ-AGENT-READ-ONLY reads the LIVE
# agent spec, so a tool added in Snowsight fails the gate too.
[doc('DOCS + agent: semantic view, documents, Cortex Search, CREATE AGENT, G3 gate')]
[group('snowflake')]
deploy-agent: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n\n' "{{connection}}"

    printf '\n=== semantic view ===\n'
    {{snow_sql}} -f "{{sql_dir}}/30_serve/02_semantic_view.sql" -D "database={{database}}"

    printf '\n=== documents: generate, stage, parse ===\n'
    uv run --quiet --with reportlab python scripts/generate_maintenance_docs.py
    {{snow_sql}} -f "{{sql_dir}}/60_docs/01_documents.sql" -D "database={{database}}"
    for f in data/maintenance_docs/*.pdf; do
        snow stage copy "$f" "@{{database}}.DOCS.MAINTENANCE_DOCS" --overwrite >/dev/null
    done
    printf 'use role WOA_ADMIN;\nuse database %s;\nuse warehouse WOA_BUILD_WH;\ncall DOCS.SP_PARSE_DOCUMENTS();\n' "{{database}}" \
        | {{snow_sql}} --stdin

    printf '\n=== search service, agent, G3 assertions ===\n'
    for f in 60_docs/02_search_service 60_docs/03_part_procedure 70_agent/01_agent 15_quality/05_g3_assertions 15_quality/07_numbers_assertions; do
        printf '\n--- %s ---\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/${f}.sql" -D "database={{database}}"
    done

    printf '\n=== gate on the G3 assertions (T-48 is gating) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/13_run_verify_g3.sql" -D "database={{database}}"

    # The numbers gate needs the semantic view (T-24 queries it), so it runs here.
    printf '\n=== gate on the numbers assertions (T-20..T-25, T-86) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/15_run_verify_numbers.sql" -D "database={{database}}"

    printf '\nagent deployed: %s.GEN.WOA_OPS_AGENT\n' "{{database}}"

# APP schema: the Streamlit surfaces. Depends on Q-39 being answered.
# Implements: US-38..US-43, US-90..US-92 (funnel, metric, baseline comparison)
[doc('APP schema: the Streamlit surfaces')]
[group('snowflake')]
deploy-app: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n\n' "{{connection}}"
    # Warehouse runtime, set explicitly in SQL (I-17): the container runtime
    # needs pypi.org, and this trial account can have no external access.
    {{snow_sql}} -f "{{sql_dir}}/80_app/01_streamlit.sql" -D "database={{database}}"
    for f in app/streamlit_app.py app/environment.yml; do
        snow stage copy "$f" "@{{database}}.APP.WOA_APP_STAGE" --overwrite
    done
    # The theme must sit at .streamlit/config.toml beside the main file.
    snow stage copy app/.streamlit/config.toml "@{{database}}.APP.WOA_APP_STAGE/.streamlit/" --overwrite
    {{snow_sql}} -f "{{sql_dir}}/80_app/02_create_streamlit.sql" -D "database={{database}}"
    printf '\n=== verify runtime and existence (a clean exit is not proof) ===\n'
    snow sql -q "describe streamlit {{database}}.APP.WOA_COMMAND_CENTER" --format json \
        | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print("runtime:", r["runtime_name"]); assert r["runtime_name"]=="SYSTEM$WAREHOUSE_RUNTIME", "wrong runtime"'
    printf '\napp deployed: Snowsight > Projects > Streamlit > WOA_COMMAND_CENTER\n'

# Re-apply only what changed since the last deploy. The everyday command.
# Must never drop or recreate anything holding data.
[doc('Re-apply only what changed since the last deploy. The everyday command')]
[group('snowflake')]
update *ARGS: _resolve-db (_todo "update" "US-44")

# Post-deploy assertions against the live target: does what the plan claims
# exists actually exist, and do the gating tests pass against it?
# Implements: T-89 (a stranger can run it) · docs/07-quality
#
# IMPLEMENTED for the G1 data-quality suite (T-1, T-7, T-8, T-9, T-11, T-12,
# T-13, T-62, T-64..T-67) and the G2 model suite (T-10, T-14..T-17, T-19). The
# engine, agent and app gates land with their own layers.
#
# Exits non-zero on a single failed assertion, via OPS.SP_ASSERT_QUALITY_GATE,
# which RAISEs. A verify step that prints failures and then succeeds is the same
# defect as a placeholder that silently passes.
[doc('Post-deploy assertions against the live target, incl. the gating tests')]
[group('snowflake')]
verify: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n\n' "{{connection}}"
    printf '\n=== G1: data quality ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/10_run_verify.sql" -D "database={{database}}"

    # Each suite gates itself, because OPS.SP_ASSERT_QUALITY_GATE checks the
    # LATEST run in DQ_RESULT. Running both suites and then gating once would
    # silently check only the second one.
    printf '\n=== G2: model ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/11_run_verify_ml.sql" -D "database={{database}}"

    printf '\n=== G4: engine (T-60 gating) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/12_run_verify_engine.sql" -D "database={{database}}"

    printf '\n=== Answers: semantic view, documents, agent (T-37, T-42, T-48 gating) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/13_run_verify_g3.sql" -D "database={{database}}"

    printf '\n=== G3: the numbers are trustworthy (T-20..T-25, T-86, T-87, T-94) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/15_run_verify_numbers.sql" -D "database={{database}}"

    printf '\n=== G4: approval-gated writes (T-29, T-33, T-35 gating) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/14_run_verify_action.sql" -D "database={{database}}"
    just _role-writes-refused

    printf '\n=== G4: the plan is never invented (T-71, T-31 gating; T-72, T-74, T-75) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/16_run_verify_planning.sql" -D "database={{database}}"

    printf '\nverify passed against %s.\n' "{{database}}"

# ACTION: the approval procedures — the ONLY write path (ADR-0005, M10).
# Implements: FR-32, FR-34..FR-37 · gated by 15_quality/14 (T-29, T-33, T-35 gating)
# Needs deploy-engine (the guards read ENGINE) and deploy-agent (drafts cite
# the procedure documents).
[doc('ACTION: approval-gated, idempotent, audited writes, and the G4 gate')]
[group('snowflake')]
deploy-action: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n\n' "{{connection}}"
    for f in 60_docs/03_part_procedure 50_action/01_action_tables 50_action/02_action_procedures 50_action/03_action_grants 50_action/04_planning_procedures 15_quality/06_action_assertions 15_quality/08_planning_assertions; do
        printf '\n=== %s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/${f}.sql" -D "database={{database}}"
    done
    printf '\n=== gate on the action assertions ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/14_run_verify_action.sql" -D "database={{database}}"
    just _role-writes-refused

    printf '\n=== G4: the plan is never invented (T-71, T-31 gating; T-72, T-74, T-75) ===\n'
    {{snow_sql}} -f "{{sql_dir}}/15_quality/16_run_verify_planning.sql" -D "database={{database}}"
    printf '\naction layer deployed and gated in %s.\n' "{{database}}"

# T-33, behavioural half: a real INSERT into ACTION as WOA_APP and as
# WOA_AGENT. Each must FAIL, and fail for lack of privilege — a failure for
# any other reason (typo, missing warehouse) would prove nothing, so the
# error text is checked too. Lives here because a procedure cannot change role.
#
# `use secondary roles none` is essential. The human running this has
# DEFAULT_SECONDARY_ROLES = ALL, so without it `use role WOA_APP` still carries
# ACCOUNTADMIN's privileges and the INSERT succeeds — which is exactly what the
# first version of this test did (evidence 09 §5). The test is about the ROLE,
# so the session must hold only the role.
[private]
_role-writes-refused:
    #!/usr/bin/env bash
    set -uo pipefail
    printf '\n=== T-33: direct writes as WOA_APP, WOA_AGENT, WOA_SCHEDULER must be refused ===\n'
    fail=0
    for role in WOA_APP WOA_AGENT WOA_SCHEDULER; do
        # Each role on its own warehouse: WOA_SCHEDULER is deliberately denied
        # WOA_APP_WH, and a refusal at USE WAREHOUSE would never reach the INSERT.
        wh=WOA_APP_WH; [ "$role" = WOA_SCHEDULER ] && wh=WOA_BUILD_WH
        out=$(printf 'use role %s;\nuse secondary roles none;\nuse warehouse %s;\ninsert into %s.ACTION.ACT_WORK_ORDER (work_order_id, draft_id, component_id, turbine_id, part_number, procedure_doc_id, approved_by, approved_role, approved_at, status, idempotency_key) select uuid_string(), %s, %s, %s, %s, %s, current_user(), current_role(), current_timestamp(), %s, uuid_string();\n' \
            "$role" "$wh" "{{database}}" "'T33'" "'T33'" "'T33'" "'T33'" "'T33'" "'T33'" | snow sql --stdin 2>&1)
        if printf '%s' "$out" | grep -qi 'number of rows inserted'; then
            printf 'FAIL  %s WROTE to ACTION directly\n' "$role"; fail=1
        elif printf '%s' "$out" | grep -qE '\b(002003|003001) \('; then
            # Match Snowflake's error CODE, not its text: the CLI draws errors in
            # a box and wraps long messages, which split "not authorized" across
            # two lines and made the first run report a correct refusal as a
            # failure. 002003 = does not exist or not authorized; 003001 =
            # insufficient privileges.
            printf 'PASS  %s refused (%s)\n' "$role" "$(printf '%s' "$out" | grep -oE '\b(002003|003001)\b' | head -1)"
        else
            printf 'FAIL  %s failed for an unexpected reason:\n%s\n' "$role" "$out"; fail=1
        fi
    done

    # T-47: nothing destructive is reachable from the agent's role. DDL, DELETE
    # and UPDATE against objects WOA_AGENT can READ. Each is inert even if it
    # somehow ran (WHERE 1=0, a no-op comment), and each must be refused.
    printf '\n=== T-47: DDL, DELETE and UPDATE as WOA_AGENT must be refused ===\n'
    while IFS= read -r stmt; do
        out=$(printf 'use role WOA_AGENT;\nuse secondary roles none;\nuse warehouse WOA_APP_WH;\n%s;\n' "$stmt" | snow sql --stdin 2>&1)
        label=$(printf '%s' "$stmt" | cut -c1-60)
        if printf '%s' "$out" | grep -qE '\b(002003|003001) \('; then
            printf 'PASS  refused (%s): %s\n' "$(printf '%s' "$out" | grep -oE '\b(002003|003001)\b' | head -1)" "$label"
        else
            printf 'FAIL  not refused: %s\n%s\n' "$label" "$out"; fail=1
        fi
    done <<EOF
    create table {{database}}.SERVING.T47_PROBE (x int)
    delete from {{database}}.ENGINE.ENG_INCIDENT where 1 = 0
    update {{database}}.ENGINE.ENG_INCIDENT set class_reason = class_reason where 1 = 0
    alter view {{database}}.SERVING.MET_LD_EXPOSURE set comment = 'T-47 probe'
    drop view {{database}}.SERVING.MET_LD_EXPOSURE
    EOF
    exit $fail

# Generate/refresh synthetic data in the target. Deterministic seed (T-8).
#
# IMPLEMENTED (US-2..US-7, US-52). Runs GEN.SP_GENERATE_ALL, which executes the
# six generation stages in dependency order and records the run's parameters in
# GEN.GEN_RUN_CONFIG.
#
# The defaults below are not arbitrary — each was measured:
#   history=183       six months, per data-sources §3
#   seed=VWS-2026     any string; the same string reproduces the same fleet,
#                     the same degradation and the same failures
#   damage=1.8        with share=0.16 this yields 58 seeded failures, inside the
#                     40..60 band §3 calls the binding constraint. Raising the
#                     rate is the sanctioned lever, not lengthening the window
#   share=0.16        the bad-batch fraction, scaled per class by wear rate, which
#                     keeps the failure mix drivetrain-weighted at ~60% (T-7)
#   interval=10       10-minute SCADA grain. ~108M rows over six months and about
#                     4.5 minutes on an XSMALL. Pass interval=30 or 60 while
#                     iterating; the demo dataset uses 10
[doc('Generate/refresh synthetic data in the target. Deterministic seed')]
[group('snowflake')]
seed history="183" seed_value="VWS-2026" damage="1.8" share="0.16" interval="10": _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    printf 'database   : %s\n' "{{database}}"
    printf 'connection : %s\n' "{{connection}}"
    printf 'window     : %s days, seed %s\n' "{{history}}" "{{seed_value}}"
    printf 'damage     : multiplier %s, bad-batch share %s\n' "{{damage}}" "{{share}}"
    printf 'signals    : %s-minute grain\n\n' "{{interval}}"
    {{snow_sql}} -f "{{sql_dir}}/10_generate/20_run_seed.sql" \
        -D "database={{database}}" \
        -D "history_days={{history}}" \
        -D "seed={{seed_value}}" \
        -D "damage_multiplier={{damage}}" \
        -D "accel_share={{share}}" \
        -D "interval_min={{interval}}"
    printf '\ngeneration complete. Run `just verify`.\n'

# Regenerate the results summary from OPS. Never hand-written (T-92, T-95).
[doc('Regenerate the results summary from OPS. Never hand-written')]
[group('snowflake')]
results: _resolve-db
    uv run --quiet --with snowflake-connector-python python scripts/generate_results.py "{{database}}"

# Current spend, both sources summed. Warehouse metering alone under-reports
# by ~10x. Alerts NK at each $100 (Q-7).
[doc('Current spend, both credit sources summed')]
[group('snowflake')]
cost: _resolve-db (_todo "cost" "NFR-8, T-54")

# Run one .sql file against the resolved target. The only sanctioned way to run
# ad-hoc SQL, and it still goes through just and still goes through git.
#
# IMPLEMENTED. Passes `database` so the file can use <% database %> and never a
# literal (NFR-6). An undefined template variable is a hard rendering error in
# `snow`, so a missing parameter fails loudly instead of substituting empty.
#
# On batching: AGENTS.md says multi-statement SQL "silently skips statements".
# That is not reproducible on snow CLI 3.27 — each statement is echoed, the first
# failure aborts the rest, and the process exits non-zero. Verified by execution;
# recorded in STATE.md §7.
[doc('Run one .sql file against the resolved target')]
[group('snowflake')]
sql FILE: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "{{FILE}}" ]; then
        echo "error: no such file: {{FILE}}" >&2
        exit 1
    fi
    printf 'database   : %s\n' "{{database}}"
    printf 'file       : %s\n\n' "{{FILE}}"
    {{snow_sql}} -f "{{FILE}}" -D "database={{database}}"

# Drop everything this project created. Destructive, and it is the TEAM's
# database: the one the demo runs from and every developer deploys to.
#
# IMPLEMENTED (US-44 — the teardown half of T-52). No override flag. Two typed
# confirmations: the database name AND the account name, so it cannot be run
# by reflex or against the wrong account. Warehouses and roles are
# account-level and cannot be undropped. See sql/90_teardown/README.md.
[doc('Drop the team database, warehouses and roles. Destructive; two confirmations')]
[group('snowflake')]
teardown: _resolve-db
    #!/usr/bin/env bash
    set -euo pipefail

    printf 'database   : %s\n' "{{database}}"
    printf 'account    : %s\n' "{{team_account}}"
    printf 'connection : %s\n\n' "{{connection}}"
    echo 'This drops, for the WHOLE TEAM:'
    echo "  * database {{database}} and everything in it (the demo included)"
    echo '  * warehouses WOA_APP_WH, WOA_BUILD_WH'
    echo '  * the nine WOA_* roles'
    echo
    echo 'The database is recoverable with UNDROP for one day; the roles and warehouses are not.'
    echo 'Agree it with the team first (CONTRIBUTING.md > What CoCo must not decide alone).'
    echo
    printf 'Type the database name to confirm: '
    read -r typed
    if [ "$typed" != "{{database}}" ]; then
        echo "refusing: typed '$typed', expected '{{database}}'." >&2
        exit 1
    fi
    printf 'Type the account name to confirm: '
    read -r typed_acct
    if [ "$typed_acct" != "{{team_account}}" ]; then
        echo "refusing: typed '$typed_acct', expected '{{team_account}}'." >&2
        exit 1
    fi

    for f in 01_database 02_warehouses 03_roles; do
        printf '\n=== %s ===\n' "$f"
        {{snow_sql}} -f "{{sql_dir}}/90_teardown/${f}.sql" -D "database={{database}}"
    done

    printf '\nteardown complete.\n'

# --- release -----------------------------------------------------------------

# Push the current branch and open a PR into main (requires GitHub CLI: gh,
# with the `project` scope: `gh auth refresh -s project`).
[doc('Push the current branch and open a PR into main (requires gh)')]
[group('release')]
pr *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    branch="$(git symbolic-ref --quiet --short HEAD || echo HEAD)"
    if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
        echo "error: cannot open a PR from '$branch' itself; switch to a feature branch." >&2
        exit 1
    fi
    git push -u origin "$branch"
    pr_url="$(gh pr create --base main --head "$branch" --fill --assignee "@me" \
        --project "{{project_title}}" {{ARGS}})"
    echo "$pr_url"

    # Best-effort: set the PR's Iteration field to whichever iteration covers
    # today. Never fails the whole command if the project/field changes shape.
    iteration_id="$(gh api graphql -f query='
      query($field: ID!) {
        node(id: $field) {
          ... on ProjectV2IterationField {
            configuration { iterations { id startDate duration } }
          }
        }
      }' -f field="{{iteration_field_id}}" \
      --jq '.data.node.configuration.iterations' 2>/dev/null \
      | python3 -c 'import datetime, json, sys; today = datetime.date.today(); hits = [i["id"] for i in json.load(sys.stdin) if datetime.date.fromisoformat(i["startDate"]) <= today < datetime.date.fromisoformat(i["startDate"]) + datetime.timedelta(days=i["duration"])]; print(hits[0] if hits else "")' \
      || true)"
    if [ -n "$iteration_id" ]; then
        gh project item-edit "{{project_number}}" --owner "{{project_owner}}" \
            --url "$pr_url" \
            --field-id "{{iteration_field_id}}" \
            --iteration-id "$iteration_id" >/dev/null
    else
        echo "warning: could not resolve the current iteration; set it manually." >&2
    fi

# Build sdist + wheel into dist/
[group('release')]
build:
    uv build

# Remove build/test/cache artifacts
[group('release')]
clean:
    rm -rf dist build .pytest_cache .ruff_cache .mypy_cache htmlcov .coverage coverage.xml
    find . -type d -name __pycache__ -exec rm -rf {} +

# --- internal ----------------------------------------------------------------

# Print the target and REFUSE any account other than the team's. The account
# rule (AGENTS.md > Deployment) is enforced here, not just written down: every
# Snowflake recipe depends on this, so none can run against a trial account.
[private]
_resolve-db:
    #!/usr/bin/env bash
    set -euo pipefail
    acct=$(snow sql -q "select current_organization_name() || '-' || current_account_name() as a" --format json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["A"])' 2>/dev/null || true)
    if [ "$acct" != "{{team_account}}" ]; then
        echo "refusing: this connection is on account '${acct:-unknown}', not {{team_account}}." >&2
        echo "  Set SNOWFLAKE_DEFAULT_CONNECTION_NAME to your connection for {{team_account}}." >&2
        exit 1
    fi
    printf 'database   : %s   (team database on %s)\n' "{{database}}" "$acct"

# Fail loudly for an unimplemented deployment recipe, naming what implements it.
[private]
_todo NAME REF:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "not implemented: just {{NAME}}" >&2
    echo "  implemented by : {{REF}}" >&2
    echo "  contract       : idempotent, prints its target, one statement per call" >&2
    echo "  see            : docs/03-architecture/deployment.md, AGENTS.md > Deployment" >&2
    echo "" >&2
    echo "Placeholders exit non-zero on purpose. A deploy command that silently" >&2
    echo "succeeds without deploying is worse than one that is missing." >&2
    exit 1
