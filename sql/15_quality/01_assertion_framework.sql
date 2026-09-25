-- =============================================================================
-- 15_quality / 01 — data-quality assertion framework           STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : NFR-14, and the runner behind the G1 tests
-- Proves     : T-1, T-7, T-8, T-9, T-11, T-12, T-13, T-62, T-64..T-67
-- Authority  : docs/07-quality/testing-and-validation.md §1 ("data quality: SQL
--              assertions in OPS, run after every generation and refresh"),
--              docs/04-data/data-sources-and-synthetic-data.md §6
-- Parameter  : <% database %>
--
-- These are ASSERTIONS, NOT HOPES. §6 of data-sources lists one per
-- reference-solution failure, and each row below names the test it satisfies and
-- the failure it prevents, so a reviewer can check the claim rather than trust it.
--
-- Naming follows 04-code.md §3 (`DQ_<subject>` in `OPS`), added there in the same
-- change as this file — the plan had no convention for assertion objects.
--
-- WHY A TABLE AND NOT A PILE OF SELECTS. Every assertion writes a row to
-- OPS.DQ_RESULT with its measured value, its threshold and its verdict. That
-- makes the outcome queryable ("has T-8 ever failed on this dataset?"), lets
-- `just verify` exit non-zero on a single failure, and stops the suite from
-- degenerating into output a human has to read and interpret. A test whose result
-- is prose is a test that gets skipped.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- DQ_ASSERTION — the catalogue: what we check and why.
-- ---------------------------------------------------------------------------
create table if not exists OPS.DQ_ASSERTION (
    assertion_id    varchar(40)   not null,
    test_id         varchar(20)   not null,
    gate            varchar(10),
    title           varchar(200)  not null,
    prevents        varchar(500),
    is_gating       boolean       not null default false,
    is_synthetic    boolean       not null default true,
    constraint pk_dq_assertion primary key (assertion_id)
);

-- ---------------------------------------------------------------------------
-- DQ_RESULT — one row per assertion per run, with the number behind the verdict.
-- ---------------------------------------------------------------------------
create table if not exists OPS.DQ_RESULT (
    run_id          varchar(40)   not null,
    assertion_id    varchar(40)   not null,
    test_id         varchar(20)   not null,
    run_at          timestamp_ntz not null,
    passed          boolean       not null,
    measured_value  number(20,6),
    threshold_value number(20,6),
    detail          varchar(1000),
    is_synthetic    boolean       not null default true
);

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-RI-FACTS',      'T-1',  'G1', 'Referential integrity across all facts and dimensions',
            'Facts pointing at dimension keys that do not exist', false),
        ('DQ-ROWCOUNT',      'T-1',  'G1', 'Every table expected to hold rows holds rows; every signal has data',
            '51 of 54 sensors with no data', false),
        ('DQ-WO-PER-FAIL',   'T-7',  'G1', 'Every seeded failure has a corrective work order',
            'Sensor record and maintenance history disagreeing', false),
        ('DQ-DRIVETRAIN',    'T-7',  'G1', 'Failure mix is drivetrain-weighted',
            'A uniform failure mix that contradicts the fleet profile', false),
        ('DQ-DEGRADATION',   'T-8',  'G1', 'Degradation trends before every seeded failure',
            'A decay term evaluating to zero for every row', true),
        ('DQ-DAMAGE-CORR',   'T-9',  'G1', 'Failure correlates with accumulated damage, not with asset ID',
            'Health as a function of primary key', false),
        ('DQ-FRESHNESS',     'T-11', 'G1', 'Data reaches the generation date across every fact',
            'Telemetry ending 9 months in the past; a last-24-hours panel returning zero rows', true),
        ('DQ-NO-FUTURE',     'T-11', 'G1', 'No fact row is dated after the generation instant',
            'An open-alarms panel showing events that have not happened', false),
        ('DQ-THRESHOLDS',    'T-12', 'G1', 'Every downstream threshold is crossed by real rows',
            'vibration > 1.5 asserted against a maximum of 0.70', false),
        ('DQ-SYNTHETIC',     'T-13', 'G1', 'Every row carries the synthetic marker',
            'Synthetic data that cannot be told apart from real data', false),
        ('DQ-ALARM-SCHEMA',  'T-62', 'G1', 'All four alarm sources conform to the normalised schema',
            'Four sources that cannot be compared', false),
        ('DQ-SEEDED-DIP',    'T-64', 'G1', 'The seeded site-wide grid dip is present and site-scoped',
            'A correlator with nothing to correlate, or 28 incidents instead of one', false),
        ('DQ-SEEDED-CASCADE','T-64', 'G1', 'The seeded sensor-fault code cascade is present and tightly timed',
            'A cascade that cannot be distinguished from unrelated alarms', false),
        ('DQ-SEEDED-CHATTER','T-65', 'G1', 'The seeded chattering signature is present, and single trips exist to contrast with',
            'A noise labeller that finds nothing, or everything', false),
        ('DQ-SEEDED-STAND',  'T-66', 'G1', 'The seeded standing alarm is open, unacknowledged and beyond threshold',
            'A standing-alarm rule with no positive case', false),
        ('DQ-SEEDED-FLOOD',  'T-67', 'G1', 'The seeded flood is concentrated at one site, not fleet-wide',
            'A flood label that fires fleet-wide whenever one site is busy', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);
