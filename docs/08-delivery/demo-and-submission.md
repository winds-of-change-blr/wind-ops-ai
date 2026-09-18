# Demo & Submission

> **Status:** Draft v0.4 · **Owner:** NK · **Last updated:** 2026-09-18
>
> Two separate obligations, easy to conflate:
>
> | Stage | Due | Deliverable |
> | --- | --- | --- |
> | **Prototype submission** | **Sun 4 Oct 2026, 11:59 PM IST** | A **deck** plus a **documented GitHub repo** (Official Rules §4.5a, §4.5b) |
> | **Grand Finale** | 27–30 Oct, if shortlisted | A **live** demo before judges. Pre-recorded demos may not be accepted (§4.5c) |
>
> `problem-statement.md` also records a 5-minute / ≥30-second-live-demo format from the team's T&C
> summary. Where the two differ we follow `problem-statement.md` per team decision (`I-1`), and we
> prepare for the shorter, stricter reading: **5 minutes total, including a live demo.**

---

## 1. What we submit on D15

| Item | Owner | Notes |
| --- | --- | --- |
| **Deck** (PPT or similar) | NK | **Drafted on D1 as a specification**, not written on D14 as a description. §3 |
| **Judge-facing root `README`** | NK | Pitches in 60 seconds; runnable setup steps; "the data is synthetic" up front. `T-89` — verified by someone who did not write it |
| **2-minute recorded walkthrough** | NK | `GS-4` then `GS-1`. Not a substitute for the live Finals demo, but it means a judge who runs nothing still sees it work |
| **Generated results summary** | NK | Model metrics, compression with failures-suppressed, gating tests passing, credits consumed — produced from `OPS`, not hand-written. This is `E9`'s "effective results" |
| GitHub repository | NK | Complete source, judged **runnable from the README** |
| Dataset list with licences | NK | Official Rules §4.4b |
| CoCo evidence | NK | One entry per phase, each with **verifiable session and request IDs** |

**The scoring surface is these seven items.** A judge gives an entry 5–15 minutes and will not read
`docs/`. That is why they are Musts (`M13`) rather than a checklist, and why the deck is written first.

**Aim to submit on Fri 2 Oct (D15)**, not on the deadline. `R-9`.

## 2. The demo — 5 minutes

Structure it so that if we are cut off at any point, what has already been shown is the strongest
part. **The alarm flood goes first**, because it is the felt pain — it earns the rest of the story.

| Time | Beat | Shows | Criterion |
| --- | --- | --- | --- |
| 0:00–0:25 | **A day of alarms, as a funnel.** 900 raw alarms → 14 incidents → **3 actionable, 2 undetermined** — one shape, with **"real failures suppressed: 0"** beside the compression figure | The funnel + noise header | `E1`, **`E3`**, `E8` |
| 0:25–0:45 | **Open one nuisance, then one we're unsure about.** A chattering pitch alarm: 31 trips, all auto-reset, no CMS corroboration at matched load, risk low. Then: *"and this one we're not sure about — it stays in the queue"* | Evidence panel | **`E7`**, `E2` |
| 0:45–0:55 | **Watch a guard refuse.** Try to suppress an alarm on an elevated-risk asset — **refused, with the reason on screen** | Refusal message | **`E2`**, `E8` |
| 0:55–1:10 | **The stakes.** VWS **designs and manufactures** turbines and maintains its own fleet. 97% guarantee, LD exposure | Fleet view | `E1`, `E6` |
| 1:10–1:30 | **Triage ranked by money**, not severity. Both orderings side by side | `ENG_ALERT_RANKED` | `E3` |
| 1:30–2:10 | **A real prediction, explained.** `KA-CTD-T07` gearbox, 30-day horizon, drivers with magnitudes — **and the held-out metric on screen beside the score** | Drivers panel — **same panel as 0:25** | **`E2`** |
| 2:10–2:30 | **And here's what a rule would have done.** A vibration threshold flags 47 components; the model flags 6; five of them failed. The rule missed two and cried wolf 41 times | Baseline comparison | **`E2`** |
| 2:30–3:05 | **Why, with a citation.** Similar failure on another serial from the same supplier batch; up-tower procedure cited to document and section | Agent answer | `E3` |
| 3:05–3:40 | **Planned, overridden, then approved.** Suggested windows with risk-left-uncovered before and after. **Reject one with a reason** — it stays visible. Approve another. **Show the audit row** | Schedule surface + `AUD_ACTION` | `E3`, `E8`, `E6` |
| 3:40–4:00 | **What the agent cannot do**, then the closing number: *"43 of 52 failures flagged, median 21 days of lead time, ₹X of LD exposure identified before it crystallised."* | Architecture slide + aggregate outcome | **`E2`**, `E6`, `E9` |
| 4:00–5:00 | **Q&A** | — | `E5`, `E9` |

**Three lines carry the pitch:** *the data is synthetic; the system is not.* · *a triage system that
never says "I don't know" is lying.* · *compression alone is trivially achieved by suppressing
everything — so we never show it alone.*

Six deliberate choices in that order. The **funnel goes first** because the flood is the felt pain and
one shape communicates it faster than any sentence. The **guard refusal at 0:45** converts our safety
claim into something watched rather than asserted. The **manufacturing framing lands at 0:55**, before
OEE is mentioned. The **baseline comparison at 2:10** is the most persuasive twenty seconds available
to us — it is the difference between "we built a model" and "the model earns its place". The
**rejection at 3:05** is the moment human-in-the-loop stops being a slogan. And the **closing number**
is the one a judge repeats to another judge.

### The 30-second cut

If time collapses, beats 1 and 2 alone are a complete story: a flood becomes a short honest list, and
here is why one item was set aside. That is the minimum viable demo. **If you get 60 seconds, add
beat 6 (the baseline comparison).**

### What we will be asked, and the answer

| Likely question | Answer |
| --- | --- |
| "Is the prediction real, or a rule?" | Trained classifier, held-out evaluation, and the test requires beating a **trivial single-signal rule** — not just random. **Slide 9 shows the comparison**, and the metric is on screen |
| **"Why Streamlit and not a real web app?"** | Because we tested the alternative. Snowflake App Runtime returns `APPLICATION SERVICE not available for trial accounts`; plain SPCS containers *are* available and we declined them — under SiS the app runs as the **viewer's** role, so least privilege is a property of the deployment rather than of code we would have had to write and then ask you to trust. [`ADR-0020`](../03-architecture/decisions/adr-0020-app-platform.md) |
| "How do I know it isn't hiding real problems?" | A blocking test asserts no seeded real failure was ever suppressed or dismissed. Zero tolerance, and the build fails if it hits |
| "Could the agent book something wrong?" | It holds no write privilege anywhere. Suggestions come only from engine-produced windows, and a human approves |
| "Is this real-time?" | One incremental path with a declared target lag, and the refresh time is on screen. The rest is batch, and we say so |
| "Why is OEE a wind metric?" | It isn't — OEE is a factory metric. This is our declared adaptation, and here is what each factor catches |
| "What did you choose not to build?" | Two things, with reasons: the dismissal-learning loop, because we would have had to seed the dismissals ourselves; and two alarm sources that added cost without evidence |

### What we deliberately do not do in the demo

| Not doing | Why |
| --- | --- |
| Mention the reference solution | `R-REF-5`. Differentiation must be self-evident |
| Claim autonomous action | Prohibited by design, and the approval gate *is* the story |
| Quote a single headline accuracy figure | Meaningless under this class imbalance |
| Show a page whose numbers we cannot explain | `NFR-15` |
| Narrate a write that did not happen | The exact defect we differentiate against |

## 3. Deck outline

Eleven slides. Judges read decks at speed, so one idea per slide.

| # | Slide | Content |
| --- | --- | --- |
| 1 | Title | Wind Ops AI · team · problem statement · "synthetic data" stated up front |
| 2 | The business | VWS **designs and manufactures** turbines, and maintains its own fleet under availability guarantees. Fictional, modelled on documented Indian wind O&M patterns |
| 3 | The problem in money | Silos → late detection → crane campaign → LD. The ₹ arithmetic, inputs marked *(illustrative)* |
| 4 | **The flood** | The funnel: 900 → 14 → 3 actionable + 2 undetermined. Compression **and** real-failures-suppressed, side by side |
| 5 | What we built | The container diagram |
| 6 | **The one rule** | Engine decides state; model explains it; human approves |
| 7 | **What the agent cannot do** | No write grant anywhere. SQL validated before execution. Candidates only. Absence as deliberate design |
| 8 | Real prediction | Damage-driven data, **two baselines including a trivial rule**, held-out metric, lead-time distribution |
| 9 | **Rule versus model** | What a threshold rule flags, what the model flags, and how many of each failed. The most persuasive slide in the deck |
| 10 | Drivers, evidence and citations | The one reusable evidence panel, in its three contexts |
| 11 | From prediction to planned work | Suggested change, its evidence, risk left uncovered before/after, reject-with-reason, approve → audit row |
| 12 | Turbine OEE | Our adaptation, declared as such, with what each factor catches |
| 13 | CoCo across the lifecycle | Four phases with **verifiable session IDs**; four reusable skills; the CLAIMED/DECLINED table |
| 14 | **Results** | The generated summary, led by the **aggregate outcome sentence** |
| 15 | Honesty slide | What we do **not** claim, and what we deliberately declined to build — `W13`, `W15` and **the containerised web app** (`ADR-0020`), each with its reason |

Slide order follows [evaluation-traceability.md](evaluation-traceability.md), so each criterion is
touched and the 40%-weighted one is touched four times (slides 7, 8, 9, 14).

Five slides are unusual, all deliberate. **Slide 4** leads with pain rather than architecture. **Slide
7** reframes absence as design — the one place restraint can score. **Slide 9** is the one that earns
the model its place. **Slide 14** turns "we built it" into measured outcomes. **Slide 15** states the
limits before a judge finds them, including the two things we refused to build and why.

## 4. Golden scenarios

Defined in [personas-and-journeys.md §3](../01-business/personas-and-journeys.md#3-golden-scenarios).
`GS-1` is the demo; the rest are rehearsed fallbacks so one misbehaving asset does not end the run.

| ID | Use in the demo |
| --- | --- |
| **`GS-4`** | **The opening beat.** A day of alarms across the fleet collapsing to a short actionable list, with one nuisance and one undetermined opened to show why |
| `GS-1` | **The spine.** Gearbox HSS bearing, caught 14+ days out, planned up-tower in a low-wind window |
| `GS-2` | Backup for the "why" beat — same failure mode on another serial from one supplier batch |
| `GS-3` | **Folded into `M10`'s season mode.** Shown if the schedule beat has room: three components bundled into one pre-season crane campaign |
| `GS-5` | Strongest answer to *"what does this catch that a dashboard wouldn't?"* — yaw misalignment losing energy with full availability and no alarm |

## 5. Fallbacks

Full sequence in [deployment.md §7](../03-architecture/deployment.md#7-demo-day-runbook). The rules:

| Failure | Response |
| --- | --- |
| A view is slow | Keep talking; the story is the ranking, not the render |
| The agent fails | Switch to the in-region model, or read the pre-verified answer from the screenshot **and say that is what you are doing** |
| The write path fails | State it plainly and move on. **Never** narrate a write that did not happen |
| **The MCP notification fails** | **Skip it without comment.** It is optional by design and never on the critical path |
| **The nightly digest is stale** | Say so — the freshness stamp is on screen anyway. `NFR-18` exists so this is visible rather than embarrassing |
| The app will not load | Local Streamlit against the same account |
| Everything fails | Walk the architecture slide and the screenshots. Be explicit that the live system is down |

Every one of these is exercised at least once before the demo (`T-53`).

## 6. Submission checklist

Run on D15.

- [ ] `just check` green
- [ ] All **eighteen** gating tests pass ([requirements §5](../02-functional/requirements.md#5-the-requirements-that-gate-the-milestone))
- [ ] **`T-94`: the baseline comparison reconciles to the evaluation run**
- [ ] **`T-96`: the guard refusal is reachable and visible in the UI**
- [ ] Aggregate outcome sentence generated and reconciling (`T-95`)
- [ ] **Cold external scoring run completed on D14, findings triaged** (`US-97`)
- [ ] **`T-89`: someone who did not write the README follows it from a clean clone and succeeds**
- [ ] Setup runs **twice** in a clean database; teardown removes everything (`T-52`)
- [ ] Results summary generated from `OPS` and reconciling to it (`T-92`)
- [ ] 2-minute walkthrough recorded (`T-90`)
- [ ] Every criterion `E1`–`E9` maps to an artefact and a demo moment (`T-93`)
- [ ] No secrets in git, history included (`T-56`)
- [ ] Every dependency and dataset listed with its licence (`T-59`)
- [ ] README setup steps followed by someone who did not write them
- [ ] "Synthetic data" stated in the repo, the app and the deck
- [ ] Every *(illustrative)* figure labelled
- [ ] No claim in the UI or deck that the code does not support
- [ ] CoCo evidence present for all four phases
- [ ] Deck complete, including the honesty slide
- [ ] Demo rehearsed twice, end to end, without intervention
- [ ] Every degraded mode exercised once (`T-53`)
- [ ] Official Rules re-read for amendments (`Q-2`)
- [ ] All members registered (`Q-3`, `Q-13`)
- [ ] Submitted, with confirmation screenshotted

## 7. Open questions

| ID | Question | Owner |
| --- | --- | --- |
| `Q-70` | Does the submission portal want a video, or only a deck and repo link? Re-check before D14 | NK |
| `Q-71` | Who presents at the Finals if shortlisted? Recommendation: NK narrates, JP drives the screen | NK |
| `Q-72` | Do we record a walkthrough as a deck asset, given pre-recorded demos may not be accepted at Finals? Recommendation: yes — useful for the prototype submission, never a substitute live | NK |
