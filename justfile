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

# Push the current branch and open a PR into main (requires GitHub CLI: gh)
pr *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    branch="$(git symbolic-ref --quiet --short HEAD || echo HEAD)"
    if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
        echo "error: cannot open a PR from '$branch' itself; switch to a feature branch." >&2
        exit 1
    fi
    git push -u origin "$branch"
    gh pr create --base main --head "$branch" --fill --assignee "@me" {{ARGS}}

# Build sdist + wheel into dist/
build:
    uv build


# Remove build/test/cache artifacts
clean:
    rm -rf dist build .pytest_cache .ruff_cache .mypy_cache htmlcov .coverage coverage.xml
    find . -type d -name __pycache__ -exec rm -rf {} +
