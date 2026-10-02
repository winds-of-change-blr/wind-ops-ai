# Skills

Reusable CoCo skills we publish. Clearly documented, reusable skills are the **headline
bonus** in this hackathon, so treat them as a deliverable, not a by-product.

## Layout

```
skills/
└── <skill-name>/
    ├── SKILL.md        # what it does, when to use it, inputs, steps, outputs
    ├── EXAMPLE.md      # a worked example with real output
    └── TEST.md         # a prompt plus the expected result
```

## Bar for "published" (NFR-13)

A skill is done when:

- [ ] `SKILL.md` states its purpose, inputs, outputs and limits in plain language
- [ ] An example shows real output, not a description of output
- [ ] A test prompt exists, and **a teammate who did not write the skill** got the expected
      result from it (T-19)
- [ ] It works on a fresh account, with no hidden dependency on our data
- [ ] It is listed in [the CoCo usage plan](../docs/06-coco/coco-usage-plan.md)

## Published

| Skill | One line | Real output | Teammate test (T-19) |
| --- | --- | --- | --- |
| [`approval-gated-agent-tools`](approval-gated-agent-tools/SKILL.md) | An agent proposes; only a human role applies, through guarded, idempotent, audited procedures | [EXAMPLE](approval-gated-agent-tools/EXAMPLE.md) | [pending](approval-gated-agent-tools/TEST.md) |
| [`alarm-noise-triage`](alarm-noise-triage/SKILL.md) | Alarm stream to classified incidents, with "real failures hidden" always beside compression | [EXAMPLE](alarm-noise-triage/EXAMPLE.md) | [pending](alarm-noise-triage/TEST.md) |
| [`semantic-view-audit`](semantic-view-audit/SKILL.md) | Coverage and fix list for a semantic view before Analyst relies on it | [EXAMPLE](semantic-view-audit/EXAMPLE.md) | [pending](semantic-view-audit/TEST.md) |

Each skill takes object names as inputs and depends on nothing in our data. Each `TEST.md` builds
its own scratch fixture, so it runs on a fresh account.

**Where they are published:** here. The repository is public, which closes `Q-8`. To use one, copy
the folder into your workspace's `skills/` or into `~/.snowflake/cortex/skills/`, or invoke it by path.

Backlog, not shipped: `synthetic-degradation-data` and `metric-parity-check` (see
[coco-usage-plan §5](../docs/06-coco/coco-usage-plan.md)).

## Discovery path

CoCo scans a workspace folder for `SKILL.md` files. Confirm where your CLI version looks
before assuming `skills/` is picked up automatically — see
[coco-setup.md §6](../docs/06-coco/coco-setup.md).
