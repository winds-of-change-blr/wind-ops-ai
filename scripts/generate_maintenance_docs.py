"""Generate the synthetic maintenance document corpus as real PDF files.

US-27: "synthetic documents as real files". The corpus is regenerated from this
script, never hand-edited, so what the agent cites is reproducible.

Every part number, lead time, crane flag and alarm code below is copied from
RAW.DIM_PART / RAW.DIM_ALARM_CODE, so a cited procedure and the data it sits
beside cannot contradict each other. SYNTHETIC — fictional OEM (AGENTS.md rule 5).

Run:  uv run --with reportlab python scripts/generate_maintenance_docs.py
"""

from __future__ import annotations

from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

OUT = Path(__file__).resolve().parent.parent / "data" / "maintenance_docs"

BANNER = "SYNTHETIC DOCUMENT — fictional OEM Vayuveda Wind Systems. Not for real-world use."

# (doc_id, title, applies_to, [(section heading, [paragraphs]), ...])
DOCS: list[tuple[str, str, str, list[tuple[str, list[str]]]]] = [
    (
        "VWS-MP-GBX-014",
        "Up-tower replacement of the gearbox high-speed-shaft (HSS) bearing",
        "Platforms VW-3.0 and VW-2.1 · Component class GBX",
        [
            (
                "1. Scope",
                [
                    "Replacement of the gearbox HSS bearing (part PT-GBX-BEAR-HSS) without removing the gearbox. "
                    "This is an UP-TOWER repair: no crane is required. Lead time for the part is 60 days, so the "
                    "part must be ordered when the risk score first reaches the MEDIUM band, not when it fails.",
                ],
            ),
            (
                "2. When to use this procedure",
                [
                    "Use when CMS alarms CM-VB-001 (GBX HSS vibration high) or CM-VB-002 (GBX HSS vibration alarm) "
                    "are corroborated by rising band energy at matched load, and oil debris (CM-OD-001) is below alarm. "
                    "If oil debris is at alarm (CM-OD-002) the damage may extend to the gear teeth: use VWS-MP-GBX-021.",
                ],
            ),
            (
                "3. Safety",
                [
                    "Lock out and tag out the turbine and apply the rotor lock before entering the nacelle. "
                    "Two technicians minimum. Work at height rescue kit must be in the nacelle.",
                ],
            ),
            (
                "4. Procedure",
                [
                    "4.1 Drain gearbox oil to below the HSS level and sample it for particle analysis.",
                    "4.2 Remove the HSS cover and the brake disc. Record bearing temperature history from SCADA.",
                    "4.3 Extract the bearing with the hydraulic puller; inspect the shaft seat for fretting.",
                    "4.4 Induction-heat the new bearing to 110 °C and fit. Allow to cool before torquing the cover.",
                    "4.5 Refill with fresh oil and run in at 50% power for 4 hours, monitoring CMS band energy.",
                ],
            ),
            (
                "5. Duration and crew",
                [
                    "Typical duration 2 days on site with a crew of 2. Weather window: wind below 12 m/s at hub height.",
                ],
            ),
        ],
    ),
    (
        "VWS-MP-GBX-021",
        "Gearbox exchange (crane campaign)",
        "Platforms VW-3.0 and VW-2.1 · Component class GBX",
        [
            (
                "1. Scope",
                [
                    "Complete exchange of the gearbox assembly (part PT-GBX-FULL). Requires a main crane. "
                    "Part lead time is 120 days. Bundle with other crane work at the same site where possible.",
                ],
            ),
            (
                "2. When to use this procedure",
                [
                    "Use when oil debris is at alarm (CM-OD-002), or when HSS and IMS vibration (CM-VB-001, CM-VB-003) "
                    "rise together, indicating damage beyond a single bearing.",
                ],
            ),
            (
                "3. Crane campaign planning",
                [
                    "Crane mobilisation costs more than the lift itself, so plan crane work per site, not per turbine. "
                    "Avoid the monsoon wind season (May to September) when lift windows are scarce.",
                ],
            ),
            (
                "4. Duration and crew",
                [
                    "Typical duration 5 days on site with a crew of 6, plus crane mobilisation.",
                ],
            ),
        ],
    ),
    (
        "VWS-MP-GEN-008",
        "Generator drive-end and non-drive-end bearing replacement",
        "Platforms VW-3.0 and VW-2.1 · Component class GEN",
        [
            (
                "1. Scope",
                [
                    "Replacement of generator bearings PT-GEN-BEAR-DE and PT-GEN-BEAR-NDE. Up-tower, no crane. "
                    "Lead time 30 days. A stator fault (PT-GEN-STATOR, 90 days, crane) is out of scope.",
                ],
            ),
            (
                "2. When to use this procedure",
                [
                    "Use when CMS alarm CM-VB-004 (Generator DE bearing high) is corroborated by a thermal rise at the "
                    "bearing relative to the component's own baseline at matched load.",
                ],
            ),
            (
                "3. Procedure",
                [
                    "3.1 Isolate the generator electrically and verify zero energy.",
                    "3.2 Remove the coupling guard and uncouple from the gearbox.",
                    "3.3 Replace the bearing, re-grease to specification, and check shaft alignment within 0.05 mm.",
                ],
            ),
            ("4. Duration and crew", ["Typical duration 1.5 days on site with a crew of 2."]),
        ],
    ),
    (
        "VWS-MP-GEN-012",
        "Generator stator exchange (crane campaign)",
        "Platforms VW-3.0 and VW-2.1 · Component class GEN",
        [
            (
                "1. Scope",
                [
                    "Exchange of the generator stator (part PT-GEN-STATOR). Requires a main crane to lower the generator. "
                    "Lead time 90 days. Bearing-only faults are covered by VWS-MP-GEN-008 and need no crane.",
                ],
            ),
            (
                "2. When to use this procedure",
                [
                    "Use when the generator shows a thermal rise that persists after bearing replacement, or winding insulation "
                    "resistance falls below specification. A thermal rise with CM-VB-004 alone points to the bearing first.",
                ],
            ),
            (
                "3. Planning",
                [
                    "Plan as a crane campaign (see VWS-MP-GBX-021 section 3) and order the stator as soon as the risk score "
                    "reaches the MEDIUM band: at 90 days the lead time is longer than most predicted times to failure.",
                ],
            ),
            (
                "4. Duration and crew",
                ["Typical duration 4 days on site with a crew of 5, plus crane mobilisation."],
            ),
        ],
    ),
    (
        "VWS-MP-PIT-015",
        "Pitch bearing replacement (crane campaign)",
        "Platforms VW-3.0 and VW-2.1 · Component class PIT",
        [
            (
                "1. Scope",
                [
                    "Replacement of a pitch bearing (part PT-PIT-BEAR). Requires a main crane to remove the blade. "
                    "Lead time 75 days. Battery and motor faults are covered by VWS-MP-PIT-011.",
                ],
            ),
            (
                "2. When to use this procedure",
                [
                    "Use when pitch faults (SA-PT-001) recur after the battery and motor have been cleared, or the pitch "
                    "axis shows rising friction torque against its own baseline.",
                ],
            ),
            (
                "3. Planning",
                [
                    "Blade removal needs a lift window of wind below 8 m/s. Bundle with other crane work at the site.",
                ],
            ),
            (
                "4. Duration and crew",
                ["Typical duration 3 days on site with a crew of 5, plus crane mobilisation."],
            ),
        ],
    ),
    (
        "VWS-MP-MSB-003",
        "Main shaft bearing replacement",
        "Platforms VW-3.0 and VW-2.1 · Component class MSB",
        [
            (
                "1. Scope",
                [
                    "Replacement of the main bearing (PT-MSB-BEAR). Requires a main crane to remove the rotor. "
                    "Lead time 90 days. This is the highest-consequence repair in the fleet.",
                ],
            ),
            (
                "2. When to use this procedure",
                [
                    "Use when CM-VB-005 (Main bearing vibration high) escalates to CM-VB-006 (Main bearing vibration "
                    "alarm) and the trend is sustained over 14 days at matched load.",
                ],
            ),
            (
                "3. Planning",
                [
                    "Plan as a crane campaign (see VWS-MP-GBX-021 section 3). Rotor removal needs a lift window of "
                    "wind below 8 m/s for the full lift.",
                ],
            ),
            ("4. Duration and crew", ["Typical duration 6 days on site with a crew of 6."]),
        ],
    ),
    (
        "VWS-MP-PIT-011",
        "Pitch system fault diagnosis and repair",
        "Platforms VW-3.0 and VW-2.1 · Component class PIT",
        [
            (
                "1. Scope",
                [
                    "Diagnosis of pitch system faults (alarm SA-PT-001) and replacement of the pitch battery pack "
                    "(PT-PIT-BAT, 7 days) or pitch motor (PT-PIT-MOTOR, 21 days). A pitch bearing (PT-PIT-BEAR, 75 "
                    "days) requires a crane and is out of scope.",
                ],
            ),
            (
                "2. Recurrence matters",
                [
                    "A pitch fault that auto-resets once is often a transient. A pitch fault that RECURS on the same "
                    "turbine within 14 days is a degradation pattern and must not be treated as nuisance: in the "
                    "fleet's history, recurring SA-PT-001 preceded pitch system failures by 6 to 18 days.",
                ],
            ),
            (
                "3. Procedure",
                [
                    "3.1 Read the pitch controller event log for the axis that faulted.",
                    "3.2 Test battery capacity; replace below 80% of rated capacity.",
                    "3.3 Measure motor winding resistance; replace the motor if phases differ by more than 5%.",
                ],
            ),
            ("4. Duration and crew", ["Typical duration 1 day on site with a crew of 2."]),
        ],
    ),
    (
        "VWS-MP-CNV-006",
        "Converter IGBT over-temperature response",
        "Platforms VW-3.0 and VW-2.1 · Component class CNV",
        [
            (
                "1. Scope",
                [
                    "Response to alarm SA-OT-004 (Converter IGBT over-temp): cooling system check, cooling pump "
                    "replacement (PT-CNV-PUMP, 7 days), or IGBT module replacement (PT-CNV-IGBT, 14 days).",
                ],
            ),
            (
                "2. Do not dismiss repeated over-temperature trips",
                [
                    "The converter has no condition-monitoring sensor, so over-temperature trips are the ONLY early "
                    "warning. Three or more self-clearing SA-OT-004 trips on one turbine have preceded converter "
                    "failures within 0 to 11 days. Treat them as actionable, not as chattering noise.",
                ],
            ),
            (
                "3. Procedure",
                [
                    "3.1 Check coolant level and flow; replace the cooling pump if flow is below 80% of nominal.",
                    "3.2 Inspect heat-sink fins for dust ingress, common at desert sites (RJ-JSM, GJ-KCH).",
                    "3.3 If trips continue with cooling restored, replace the IGBT module.",
                ],
            ),
        ],
    ),
    (
        "VWS-SOP-ALM-001",
        "Alarm handling and suppression policy",
        "All platforms · Remote Monitoring Centre",
        [
            (
                "1. Purpose",
                [
                    "Defines how the Remote Monitoring Centre classifies alarm incidents and when an alarm may be "
                    "suppressed. Suppression hides an alarm from the queue; it is the only action that can lose a "
                    "real failure, so it is the most tightly guarded.",
                ],
            ),
            (
                "2. Three classes",
                [
                    "ACTIONABLE: needs action. UNDETERMINED: the evidence does not decide it, so it stays in the queue "
                    "for a human and is never hidden. NUISANCE: self-clearing, uncorroborated, non-recurring noise on a "
                    "monitored component with no elevated evidence.",
                ],
            ),
            (
                "3. Never suppress",
                [
                    "Never suppress a safety-critical alarm, such as SA-YW-002 (Cable twist limit). Never suppress an "
                    "alarm on an asset with elevated evidence: an anomaly flag within 3 days, or a CMS alarm within 7 "
                    "days. Never suppress an UNDETERMINED incident.",
                ],
            ),
            (
                "4. Approval",
                [
                    "Every suppression requires human approval, is time-boxed, is reversible, and is written to the "
                    "audit trail before it takes effect.",
                ],
            ),
        ],
    ),
    (
        "VWS-SOP-CMS-002",
        "Condition-monitoring vibration alarm response",
        "All platforms · Components GBX, GEN, MSB",
        [
            (
                "1. Purpose",
                [
                    "How to respond to condition-monitoring (CMS) vibration and oil debris alarms: CM-VB-001 to "
                    "CM-VB-006, CM-OD-001 and CM-OD-002.",
                ],
            ),
            (
                "2. Compare at matched load",
                [
                    "A vibration rise at higher load is not degradation. Always compare against the component's own "
                    "baseline in the same load band before acting. A rise at matched load is the signal.",
                ],
            ),
            (
                "3. Escalation",
                [
                    "HIGH vibration: order parts if the lead time exceeds the predicted time to failure. ALARM level: "
                    "schedule the repair in the next weather window. For the procedures see VWS-MP-GBX-014, "
                    "VWS-MP-GEN-008 and VWS-MP-MSB-003.",
                ],
            ),
        ],
    ),
    (
        "VWS-CON-AV-001",
        "Contractual availability and liquidated damages",
        "All O&M contracts",
        [
            (
                "1. Availability definition",
                [
                    "Contractual availability = available hours / (period hours - excluded hours). Excluded: grid "
                    "outage, curtailment, force majeure, balance of plant, and scheduled maintenance within the annual "
                    "allowance. Corrective repair is NOT excluded and counts against Vayuveda.",
                ],
            ),
            (
                "2. Guarantee",
                [
                    "Availability is guaranteed at 95% in contract years 1 and 2, and 97% from year 3 onward, assessed "
                    "per site per contract year.",
                ],
            ),
            (
                "3. Liquidated damages",
                [
                    "For each percentage point of shortfall below the guarantee, Vayuveda pays INR 50,000 per turbine "
                    "at the site. Damages are assessed annually; any in-year figure is a run-rate estimate only.",
                ],
            ),
        ],
    ),
]


def build(doc_id: str, title: str, applies_to: str, sections: list[tuple[str, list[str]]]) -> Path:
    styles = getSampleStyleSheet()
    path = OUT / f"{doc_id}.pdf"
    story = [
        Paragraph(f"{doc_id} — {title}", styles["Title"]),
        Paragraph(applies_to, styles["Normal"]),
        Paragraph(BANNER, styles["Italic"]),
        Spacer(1, 12),
    ]
    for heading, paras in sections:
        story.append(Paragraph(heading, styles["Heading2"]))
        story.extend(Paragraph(p, styles["BodyText"]) for p in paras)
        story.append(Spacer(1, 6))
    SimpleDocTemplate(str(path), pagesize=A4, title=f"{doc_id} {title}").build(story)
    return path


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for spec in DOCS:
        print(build(*spec).name)
