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

# Build sdist + wheel into dist/
build:
    uv build


# Remove build/test/cache artifacts
clean:
    rm -rf dist build .pytest_cache .ruff_cache .mypy_cache htmlcov .coverage coverage.xml
    find . -type d -name __pycache__ -exec rm -rf {} +
