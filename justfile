# Run `just` to list commands, grouped. Requires: uv, just.
#
# Every deployment to Snowflake goes through a recipe in the `snowflake` group.
# Never run ad-hoc DDL against a shared database — see AGENTS.md > Deployment.

set unstable := true

# --- variables ---------------------------------------------------------------

# Which database this run targets. `dev` (default) resolves to your personal
# clone; `shared` is the team database and is deliberately harder to hit.
env := "dev"

# Your initials, for the personal dev clone. Override: `just initials=jp deploy`.
initials := lowercase(trim(shell("git config user.initials 2>/dev/null || echo ''")))

# The Snowflake connection from ~/.snowflake/connections.toml.
connection := env_var_or_default("SNOWFLAKE_DEFAULT_CONNECTION_NAME", "default")

# Where deployment SQL and Snowpark entrypoints live (created during build).
deploy_dir := "deploy"

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
    @printf 'env        : %s\n' "{{env}}"

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
#   2. Prints its target first, and refuses `env=shared` without confirmation.
#   3. One statement per call. Batched multi-statement SQL silently skips
#      statements — this cost us a debugging cycle during planning.

# Full stack into the resolved target, in dependency order. Idempotent.
# Implements: US-44 (deployment scripts) · docs/03-architecture/deployment.md
[doc('Deploy the full stack into the resolved target, in dependency order')]
[group('snowflake')]
deploy: _resolve-db (_todo "deploy" "US-44") && (verify)
    @echo "would run: foundation -> deploy-data -> deploy-ml -> deploy-agent -> deploy-app"

# Roles, warehouses, database, schemas, grants. Run once per environment.
# Naming authority: docs/03-architecture/04-code.md. Least privilege (NFR-3).
[doc('Roles, warehouses, database, schemas, grants. Once per environment')]
[group('snowflake')]
deploy-foundation: _resolve-db (_todo "deploy-foundation" "US-44, NFR-3")

# GEN/RAW/CURATED/SERVING: generator, tables, dynamic table (M12), semantic view.
# Implements: US-8..US-12 (generator) · US-18..US-22 · US-93 (incremental path)
[doc('GEN/RAW/CURATED/SERVING: generator, tables, dynamic table, semantic view')]
[group('snowflake')]
deploy-data: _resolve-db (_todo "deploy-data" "US-8..US-12, US-93")

# ML schema: train, evaluate, register. Writes metrics to OPS for T-15/T-17.
# Must fail loudly if the model does not beat both baselines (T-10).
[doc('ML schema: train, evaluate, register. Fails if baselines are not beaten')]
[group('snowflake')]
deploy-ml: _resolve-db (_todo "deploy-ml" "US-13..US-17, T-10")

# ENGINE/ACTION: correlator, ranking, guards, approval-gated writes, audit.
# Nothing here may grant an agent a write tool (AGENTS.md rule 2).
[doc('ENGINE/ACTION: correlator, ranking, guards, approval-gated writes, audit')]
[group('snowflake')]
deploy-engine: _resolve-db (_todo "deploy-engine" "US-53..US-73")

# DOCS + agent: Cortex Search service, semantic view wiring, CREATE AGENT.
# Read-only tools only — seven of them (docs/05-ai-ml/agents-and-tools.md).
[doc('DOCS + agent: Cortex Search service, semantic view wiring, CREATE AGENT')]
[group('snowflake')]
deploy-agent: _resolve-db (_todo "deploy-agent" "US-27..US-32")

# APP schema: the Streamlit surfaces. Depends on Q-39 being answered.
# Implements: US-38..US-43, US-90..US-92 (funnel, metric, baseline comparison)
[doc('APP schema: the Streamlit surfaces')]
[group('snowflake')]
deploy-app: _resolve-db (_todo "deploy-app" "US-38..US-43, Q-39")

# Re-apply only what changed since the last deploy. The everyday command.
# Must never drop or recreate anything holding data.
[doc('Re-apply only what changed since the last deploy. The everyday command')]
[group('snowflake')]
update *ARGS: _resolve-db (_todo "update" "US-44")

# Post-deploy assertions against the live target: does what the plan claims
# exists actually exist, and do the 18 gating tests pass against it?
# Implements: T-89 (a stranger can run it) · docs/07-quality
[doc('Post-deploy assertions against the live target, incl. the 18 gating tests')]
[group('snowflake')]
verify: _resolve-db (_todo "verify" "18 gating tests")

# Generate/refresh synthetic data in the target. Deterministic seed (T-8).
[doc('Generate/refresh synthetic data in the target. Deterministic seed')]
[group('snowflake')]
seed *ARGS: _resolve-db (_todo "seed" "US-8..US-12, T-8")

# Regenerate the results summary from OPS. Never hand-written (T-92, T-95).
[doc('Regenerate the results summary from OPS. Never hand-written')]
[group('snowflake')]
results: _resolve-db (_todo "results" "T-92, T-95")

# Current spend, both sources summed. Warehouse metering alone under-reports
# by ~10x. Alerts NK at each $100 (Q-7).
[doc('Current spend, both credit sources summed')]
[group('snowflake')]
cost: _resolve-db (_todo "cost" "NFR-8, T-54")

# Run one .sql file, ONE STATEMENT AT A TIME, against the resolved target.
# The only sanctioned way to run ad-hoc SQL, and it still goes through just.
[doc('Run one .sql file, ONE STATEMENT AT A TIME, against the resolved target')]
[group('snowflake')]
sql FILE: _resolve-db (_todo "sql" "AGENTS.md > Deployment")

# Drop everything this project created in the resolved target. Destructive.
# Must require the typed database name, and must refuse `env=shared` outright.
[doc('Drop everything this project created in the resolved target. Destructive')]
[group('snowflake')]
teardown: _resolve-db (_todo "teardown" "US-44")

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

# Resolve and print the target database. Refuses a dev target with no initials.
[private]
_resolve-db:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{env}}" in
      dev)
        if [ -z "{{initials}}" ]; then
            echo "error: no initials. Set once with:" >&2
            echo "  git config user.initials nk" >&2
            echo "or pass: just initials=nk <recipe>" >&2
            exit 1
        fi
        printf 'database   : WIND_OPS_AI_DEV_%s\n' "$(echo '{{initials}}' | tr 'a-z' 'A-Z')"
        ;;
      shared)
        printf 'database   : WIND_OPS_AI   *** SHARED ***\n'
        ;;
      *)
        echo "error: env must be 'dev' or 'shared', got '{{env}}'" >&2
        exit 1
        ;;
    esac

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
