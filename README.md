# Wind Ops AI

Wind operations AI tooling

## Requirements

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (package & environment manager)
- [just](https://github.com/casey/just) (command runner)
- [gh](https://cli.github.com/) (GitHub CLI, for `just pr`)

## Getting started

```bash
just bootstrap     # create the virtualenv, install deps, install git hooks
just check         # lint + format-check + tests
```

Run `just` with no arguments to list every command, grouped.

**Picking up work on this project?** Read [CONTRIBUTING.md](CONTRIBUTING.md) — it is the whole
workflow on one page, with CoCo prompts you can paste. Then run `just state`.

## Development

```bash
just fmt           # auto-format with ruff
just lint          # ruff lint (with --fix)
just test          # pytest
just build         # build sdist + wheel into dist/
```

## Branching & commits

`main` is protected. A pre-commit hook (`no-commit-to-branch`) blocks direct
commits to `main`/`master` — always work on a feature branch and open a PR.

Hackathon team (4 people, 15 days) — keep this lightweight, no ticket
tracker required.

**Branch names:** `<type>/<initials>/<short-desc>`

- `type` — one of `feat`, `fix`, `chore`, `docs`, `spike` (throwaway
  experiment/prototype)
- `initials` — your 2-3 letter initials, so everyone can tell whose branch
  is whose at a glance
- `short-desc` — 2-4 words, kebab-case

```
feat/nk/wind-forecast-api
fix/ab/turbine-csv-parsing
spike/cd/onnx-runtime-poc
docs/ef/setup-instructions
```

**Commit messages:** [Conventional Commits](https://www.conventionalcommits.org/),
short and imperative:

```
feat: add wind speed forecasting endpoint
fix: handle missing turbine ids in csv import
chore: bump ruff version
```

**PRs:** small and frequent beats big and late. Open a PR as soon as
something is reviewable — a day-1 partial feature is easier to merge (and
unblock others on) than a day-14 mega-branch. Run `just pr` to push the
current branch and open a PR into `main` (requires `gh`, and refuses to run
from `main`/`master` itself). Reviewers are auto-requested via
[CODEOWNERS](.github/CODEOWNERS).

**Require 2 approvals before merging.** GitHub branch protection isn't
available on our plan for this private repo, so this isn't technically
enforced — it's a team convention (see the [PR template](.github/PULL_REQUEST_TEMPLATE.md)
checklist). Don't merge your own PR until 2 people have approved it.

## Project layout

```
wind-ops-ai/
├── src/wind_ops_ai/      # package code
├── tests/                  # pytest tests
├── pyproject.toml          # project metadata, deps, tool config
├── justfile                # task runner
└── .pre-commit-config.yaml # git hooks
```

## License

MIT — see [LICENSE](LICENSE).
