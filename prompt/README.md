# Prompts

Reusable prompts for the CoCo work on this project.

| Prompt | Purpose |
| --- | --- |
| [generate-plan.md](generate-plan.md) | Produce (or rebuild) the whole planning set under `docs/`, in reviewable stages, and audit it at the end |

## How to run

First time on this machine? Follow [docs/06-coco/coco-setup.md](../docs/06-coco/coco-setup.md).

From the repository root (so CoCo picks up [`AGENTS.md`](../AGENTS.md)):

```bash
cortex
```

Then, in the session:

```
Read prompt/generate-plan.md and follow it.
```

CoCo Desktop works the same way — open this folder as the workspace and give it the same
instruction.

## Why this exists

1. **Reproducibility.** Anyone on the team can regenerate or extend the plan the same way.
2. **Evidence.** The hackathon requires CoCo in *every* phase, including planning, and judges
   look for proof. Running this prompt produces exactly that.

After a run, save the transcript and a short summary into
`docs/06-coco/evidence/planning/` using the entry template in
[the evidence log](../docs/06-coco/evidence/README.md). Get the thread id with
`cortex automation doctor` for scheduled runs, or
`cortex conversations transcript <thread_id>` for an interactive one.

## Editing these prompts

Treat them like code: change them in a PR, and say in the PR description what behaviour
changed. If a run produces a bad result, fix the prompt rather than only fixing the output —
otherwise the next run repeats the mistake.
