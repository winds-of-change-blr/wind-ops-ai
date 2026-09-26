-- =============================================================================
-- 50_action / 01 — the ACTION tables and the append-only audit    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-32, FR-34..FR-37, ADR-0005 (M10)
-- Proves     : T-30, T-33..T-35 (with 02_action_procedures and 03_action_grants)
-- Authority  : ADR-0005, docs/04-data/data-model.md §6
-- Parameter  : <% database %>
--
-- ACTION is the only schema written at runtime, and NOTHING writes it directly.
-- Every row in these tables arrives through a procedure in 02, which re-checks
-- the request against the engine, appends to AUD_ACTION first, and only then
-- changes state. No role other than the owner holds any privilege on these
-- tables (asserted by DQ-ACTION-NO-DIRECT-GRANT).
--
-- ===================== APPEND-ONLY, AND WHAT THAT MEANS HERE =================
--
-- AUD_ACTION is never updated and never deleted from; no procedure contains an
-- UPDATE or DELETE against it. Suppressions and drafts DO change status
-- (ACTIVE -> REVOKED, DRAFT -> APPROVED), but every change is a new audit row,
-- so the audit alone reconstructs the history. Nothing is ever deleted (T-30).
--
-- ===================== SELF-TEST ROWS =======================================
--
-- `just verify` exercises the real procedures (T-29, T-30, T-34, T-35), so it
-- leaves real rows. They are marked IS_SELFTEST (derived from an idempotency
-- key starting 'SELFTEST-') and the app hides them. Marking, not deleting:
-- deleting would break the append-only rule the tests exist to prove.
--
-- Uniqueness of idempotency keys is enforced by the procedures, not by the
-- constraints below: Snowflake records UNIQUE but does not enforce it.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create table if not exists ACTION.AUD_ACTION (
    audit_id          varchar(36)   not null default uuid_string(),
    event_at          timestamp_ntz not null default current_timestamp()::timestamp_ntz,
    actor_user        varchar(200)  not null,
    actor_role        varchar(200)  not null,
    on_behalf_of      varchar(200),
    action_type       varchar(40)   not null,
    object_type       varchar(40)   not null,
    object_id         varchar(200),
    idempotency_key   varchar(200),
    outcome           varchar(20)   not null,
    reason            varchar(2000),
    inputs            variant,
    evidence          variant,
    is_selftest       boolean       not null default false,
    constraint pk_aud_action primary key (audit_id)
) comment = 'Append-only audit of every ACTION request, including refusals. Written before any state change (FR-37, T-35).';

create table if not exists ACTION.ACT_SUPPRESSION (
    suppression_id    varchar(36)   not null,
    incident_id       varchar(200)  not null,
    turbine_id        varchar(20)   not null,
    alarm_code        varchar(40)   not null,
    reason            varchar(2000) not null,
    approved_by       varchar(200)  not null,
    approved_role     varchar(200)  not null,
    on_behalf_of      varchar(200),
    approved_at       timestamp_ntz not null,
    expires_at        timestamp_ntz not null,
    status            varchar(20)   not null,
    revoked_by        varchar(200),
    revoked_at        timestamp_ntz,
    revoke_reason     varchar(2000),
    idempotency_key   varchar(200)  not null,
    is_selftest       boolean       not null default false,
    constraint pk_act_suppression primary key (suppression_id),
    constraint uq_act_suppression_key unique (idempotency_key)
) comment = 'Human-approved alarm suppressions. Time-boxed (max 168 h), reversible by SP_REVOKE_SUPPRESSION, never deleted (FR-32, T-30).';

create table if not exists ACTION.ACT_WORK_ORDER_DRAFT (
    draft_id              varchar(36)   not null,
    component_id          varchar(30)   not null,
    turbine_id            varchar(20)   not null,
    site_code             varchar(10)   not null,
    component_class_name  varchar(100),
    scope                 varchar(2000) not null,
    part_number           varchar(40)   not null,
    part_name             varchar(200),
    part_lead_time_days   integer,
    requires_crane        boolean,
    stock_on_hand         integer,
    procedure_doc_id      varchar(40)   not null,
    procedure_section     varchar(300),
    risk_probability      number(10,6)  not null,
    risk_band             varchar(20)   not null,
    anomaly_flag          boolean,
    top_drivers           varchar,
    expected_loss_inr     number(38,0),
    model_version         varchar(100),
    risk_as_of_date       date          not null,
    window_status         varchar(40)   not null,
    window_note           varchar(500),
    crew_id               varchar(40),
    status                varchar(20)   not null,
    drafted_by            varchar(200)  not null,
    drafted_at            timestamp_ntz not null,
    idempotency_key       varchar(200)  not null,
    is_selftest           boolean       not null default false,
    constraint pk_act_work_order_draft primary key (draft_id)
) comment = 'Work-order drafts with the evidence snapshot that justified them (FR-34). Drafted from ENGINE.ENG_ALERT_RANKED only.';

create table if not exists ACTION.ACT_WORK_ORDER (
    work_order_id     varchar(36)   not null,
    draft_id          varchar(36)   not null,
    component_id      varchar(30)   not null,
    turbine_id        varchar(20)   not null,
    part_number       varchar(40)   not null,
    procedure_doc_id  varchar(40)   not null,
    approved_by       varchar(200)  not null,
    approved_role     varchar(200)  not null,
    on_behalf_of      varchar(200),
    approved_at       timestamp_ntz not null,
    status            varchar(30)   not null,
    idempotency_key   varchar(200)  not null,
    is_selftest       boolean       not null default false,
    constraint pk_act_work_order primary key (work_order_id),
    constraint uq_act_work_order_draft unique (draft_id),
    constraint uq_act_work_order_key unique (idempotency_key)
) comment = 'Approved work orders. One per draft, one per idempotency key (FR-35, FR-36, T-34).';

create table if not exists ACTION.ACT_DECISION (
    decision_id       varchar(36)   not null,
    subject_type      varchar(40)   not null,
    subject_id        varchar(200)  not null,
    decision          varchar(20)   not null,
    reason_code       varchar(40)   not null,
    note              varchar(2000),
    decided_by        varchar(200)  not null,
    decided_role      varchar(200)  not null,
    on_behalf_of      varchar(200),
    decided_at        timestamp_ntz not null,
    idempotency_key   varchar(200)  not null,
    is_selftest       boolean       not null default false,
    constraint pk_act_decision primary key (decision_id)
) comment = 'Confirm / dismiss / reinstate / accept / reject decisions. One table, per-subject reason vocabularies (data-model.md §6, Q-81).';

-- The T-35 fault hook. Read by the write procedures; writable only by
-- WOA_ADMIN; must be OFF after every verify run (DQ-FAULT-HOOK-OFF). It exists
-- because "the audit append failed" cannot otherwise be produced on demand.
create table if not exists OPS.OPS_TEST_HOOK (
    hook        varchar(40)  not null,
    enabled     boolean      not null,
    set_at      timestamp_ntz,
    constraint pk_ops_test_hook primary key (hook)
) comment = 'Fault-injection switches for the G4 self-tests. Must be off outside a verify run.';

merge into OPS.OPS_TEST_HOOK t
using (select 'FAIL_AUDIT' as hook) s on t.hook = s.hook
when not matched then insert (hook, enabled, set_at) values ('FAIL_AUDIT', false, current_timestamp()::timestamp_ntz);

-- What the app shows: live suppressions only, self-tests hidden.
create or replace view ACTION.ACT_V_SUPPRESSION_ACTIVE as
select suppression_id, incident_id, turbine_id, alarm_code, reason,
       approved_by, on_behalf_of, approved_at, expires_at
from ACTION.ACT_SUPPRESSION
where status = 'ACTIVE'
  and expires_at > current_timestamp()::timestamp_ntz
  and not is_selftest;
