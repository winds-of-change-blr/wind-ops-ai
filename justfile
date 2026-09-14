# Run `just` to list commands. Requires: uv, just.

# Show available commands
default:
    @just --list

# Create venv, install all deps, install git hooks
bootstrap:
    uv sync
    uv run pre-commit install

# Install / update dependencies from pyproject.toml
sync:
    uv sync

# Auto-format the codebase
fmt:
    uv run ruff format .
    uv run ruff check --fix .

# Lint (ruff). Use `just fmt` to auto-fix.
lint:
    uv run ruff check .
    uv run ruff format --check .

# Run the test suite
test *ARGS:
    uv run pytest {{ARGS}}

# Lint + test (the full local gate)
check: lint test

# Run all pre-commit hooks against all files
hooks:
    uv run pre-commit run --all-files

# Project board this repo's PRs are tracked on, and its Iteration field id
# (`gh project field-list 1 --owner winds-of-change-blr` to re-derive if the
# board is ever recreated).
project_owner := "winds-of-change-blr"
project_number := "1"
project_title := "Snowflake COCO CLI GCC 2026"
iteration_field_id := "PVTIF_lADOE5mWsc4BjYhOzhiNAXI"

# Push the current branch and open a PR into main (requires GitHub CLI: gh,
# with the `project` scope: `gh auth refresh -s project`).
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
build:
    uv build


# Remove build/test/cache artifacts
clean:
    rm -rf dist build .pytest_cache .ruff_cache .mypy_cache htmlcov .coverage coverage.xml
    find . -type d -name __pycache__ -exec rm -rf {} +
