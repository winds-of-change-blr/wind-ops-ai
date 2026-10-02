-- =============================================================================
-- 50_action / 05 — read one approved work order, for the MCP connector  STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : coco-usage-plan §4 row 5 (the woa-github MCP connector), ADR-0019
-- Parameter  : <% database %>
--
-- No role holds SELECT on an ACTION table (T-33); procedures are the only
-- interface. This one is READ-ONLY: it returns a work order, its draft
-- evidence and the APPLIED audit row that proves the approval, so a connector
-- outside Snowflake can forward a decision without ever being able to make one.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;

create or replace procedure ACTION.SP_GET_WORK_ORDER(P_WORK_ORDER_ID varchar)
returns variant
language sql
comment = 'Read-only: one work order with its draft evidence and APPLIED audit id. Writes nothing.'
execute as owner
as
$$
declare
    v variant;
begin
    select object_construct(
               'work_order_id', w.work_order_id, 'status', w.status, 'is_selftest', w.is_selftest,
               'approved_by', w.approved_by, 'approved_role', w.approved_role,
               'on_behalf_of', w.on_behalf_of, 'approved_at', w.approved_at::varchar,
               'turbine_id', w.turbine_id, 'component_id', w.component_id,
               'part_number', w.part_number, 'procedure_doc_id', w.procedure_doc_id,
               'site_code', d.site_code, 'component_class_name', d.component_class_name,
               'risk_band', d.risk_band, 'risk_probability', d.risk_probability,
               'expected_loss_inr', d.expected_loss_inr, 'top_drivers', d.top_drivers,
               'window_start', d.window_start::varchar, 'crew_id', d.crew_id,
               'audit_id', a.audit_id)
      into :v
      from ACTION.ACT_WORK_ORDER w
      join ACTION.ACT_WORK_ORDER_DRAFT d on d.draft_id = w.draft_id
      left join (select object_id, max(audit_id) audit_id
                   from ACTION.AUD_ACTION
                  where action_type = 'APPROVE_WORK_ORDER' and object_type = 'DRAFT'
                    and outcome = 'APPLIED'
                  group by object_id) a on a.object_id = w.draft_id
     where w.work_order_id = :P_WORK_ORDER_ID;
    return v;
end;
$$;

grant usage on procedure ACTION.SP_GET_WORK_ORDER(varchar) to role WOA_PLANNER;
