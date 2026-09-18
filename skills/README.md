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

## Candidates

See [coco-usage-plan.md §4](../docs/06-coco/coco-usage-plan.md) for the shortlist:
`alarm-noise-triage`, `synthetic-plant-iot-data`, `oee-semantic-view-builder`,
`maintenance-root-cause`, `approval-gated-agent-tools`, `maintenance-schedule-planner`,
`coco-evidence-logger`.

## Open question

**Where do these get published?** The bonus rewards skills *other teams can reuse*, but this
repository is private (`Q-8` in the [RAID log](../docs/08-delivery/raid-log.md)). Either
publish to a separate public repository or make this one public at submission — decide early,
because it changes how much project-specific detail belongs in each skill.

## Discovery path

CoCo scans a workspace folder for `SKILL.md` files. Confirm where your CLI version looks
before assuming `skills/` is picked up automatically — see
[coco-setup.md §6](../docs/06-coco/coco-setup.md).
