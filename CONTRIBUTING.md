# How to contribute

Implementation is done with **CoCo** (Cortex Code desktop or CLI). This page is the whole workflow:
two paths, with prompts you can paste. Nothing else to read first.

## The five steps, every time

```bash
just state                              # 1. read the handoff — what's done, what's claimed
git switch -c feat/nk/alarm-correlator  # 2. your own branch, always
# 3. edit STATE.md §2: claim your work, commit, push
#    ... work with CoCo ...
just check                              # 4. lint + tests green
just pr                                 # 5. open the PR (needs 2 approvals)
```

**Branch naming is enforced**, not just recommended: `<type>/<initials>/<short-desc>`, type one of
`feat fix chore docs spike`. A pre-commit hook rejects anything else, and a second hook blocks commits
to `main` outright. See [README · Branching & commits](README.md#branching--commits).

Claiming in [`STATE.md`](STATE.md) §2 *before* you start is the one step people skip. Skip it and two
people build the same thing — there are 15 days and no slack for that.

---

## Path A — carry on with the plan

Most work. The plan already says what to build; you are picking up the next piece.

> Read `AGENTS.md` and `STATE.md`, then run `just state`.
>
> Take the next unclaimed action from `STATE.md` §3. Before writing any code:
> confirm which story ID (`US-…`) and test ID (`T-…`) it corresponds to in
> `docs/02-functional/epics-and-stories.md` and
> `docs/07-quality/testing-and-validation.md`, and tell me both. Create the
> branch, claim the row in `STATE.md` §2, and push that claim first.
>
> Then implement it. Deployment goes through a `just` recipe in the `snowflake`
> group — never ad-hoc DDL. Run `just target` first and show me what it prints
> before touching Snowflake.
>
> Done means the named test passes, not that the code looks right. When it does:
> update `STATE.md` (§1 gates, §2 clear your claim, §5 if you created any
> Snowflake object), write the evidence entry per `AGENTS.md`, and stop before
> committing so I can review.

## Path B — something the plan does not cover

A new feature, or a change to what was planned. **The plan changes first, then the code.**

> Read `AGENTS.md`, `STATE.md` and `docs/02-functional/scope.md`.
>
> I want to add: **<describe it in one or two sentences>**.
>
> Before writing any code, tell me:
> 1. Is this already covered by an existing `US-…`? If so, stop — it's Path A.
> 2. Which scope bucket does it belong in — `M`, `S`, `C` or `W`
>    (`docs/02-functional/scope.md`)? If it is a Must, **what does it displace?**
>    We are 4 people over 15 days and the cut order in that file is deliberate.
> 3. Which evaluation criterion (`E1`–`E9`) does it serve, and does anything in
>    `docs/08-delivery/evaluation-traceability.md` already serve it better?
> 4. Does it conflict with an ADR in `docs/03-architecture/decisions/`? Say which.
>
> If it survives all four, propose the plan edits — new `FR-…`, `US-…`, `T-…`,
> scope row, and an ADR if it is a real decision — and wait for my approval
> before editing anything. Argue against it if you think it is the wrong call.

**Why the friction:** the plan is internally cross-referenced — 99 requirements, 97 stories, 96 tests,
19 ADRs, all ID-linked. Code that arrives without its IDs breaks the traceability that
`docs/08-delivery/evaluation-traceability.md` depends on, and that document is how we prove coverage to
judges.

## Path C — something is broken

> Read `AGENTS.md` and `STATE.md`. `<what is failing, and the exact error>`.
>
> Find the root cause before proposing a fix, and tell me which test *should*
> have caught this. If none would have, write that test first.

---

## What CoCo must not decide alone

Ask a human. These are in `AGENTS.md` as rules, and they are the ones that cost most when wrong.

| | |
| --- | --- |
| Editing `docs/00-hackathon/*` or `company-profile.md` | Given documents. Propose, never edit |
| `just teardown` | Drops the team database, warehouses and roles for everyone |
| Dropping scope, or changing a Must | A team decision — see `scope.md` cut order |
| Adding a dependency | `uv add`, but ask first |
| Anything touching credentials | Never in git |

## Before you open the PR

- [ ] The test named in the plan passes — `just check` green
- [ ] `STATE.md` updated: claim cleared, §5 current if you touched Snowflake
- [ ] Evidence entry written and indexed ([`AGENTS.md` · Evidence](AGENTS.md#evidence))
- [ ] Docs/ADRs changed in *this* PR, not a later one
- [ ] Conventional Commits (`feat: …`) — also hook-enforced

Then `just pr`. Two approvals to merge.

---

**Stuck on where anything lives?** [`docs/README.md`](docs/README.md) is the map.
**Stuck on what to do next?** `just state`.
