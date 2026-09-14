#!/usr/bin/env bash
# Enforce the branch naming convention documented in README.md:
#   <type>/<initials>/<short-desc>
# e.g. feat/nk/wind-forecast-api
set -euo pipefail

# symbolic-ref (unlike `rev-parse --abbrev-ref HEAD`) works correctly even
# before the first commit exists (an "unborn" branch).
branch="$(git symbolic-ref --quiet --short HEAD || echo HEAD)"

# Protected branches are exempt (no-commit-to-branch already blocks commits to
# them); detached HEAD (e.g. rebase) is also exempt.
case "$branch" in
  main|master|HEAD)
    exit 0
    ;;
esac

pattern='^(feat|fix|chore|docs|spike)/[a-z]{2,4}/[a-z0-9]+(-[a-z0-9]+)*$'

if ! [[ "$branch" =~ $pattern ]]; then
  echo "error: branch name '$branch' does not match the required convention." >&2
  echo "  expected: <type>/<initials>/<short-desc>" >&2
  echo "  type       one of: feat, fix, chore, docs, spike" >&2
  echo "  initials   2-4 lowercase letters" >&2
  echo "  short-desc 2+ words, kebab-case" >&2
  echo "  example:   feat/nk/wind-forecast-api" >&2
  echo "See README.md#branching--commits for details." >&2
  exit 1
fi
