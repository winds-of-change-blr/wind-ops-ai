-- =============================================================================
-- 15_quality / 05 — G3 assertions: semantic view, documents, agent STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the checkable half of G3
-- Proves     : T-42 (descriptions present, sample values real), T-37 (sections
--              resolvable), T-48 (GATING: no write tool), doc/data consistency
-- Authority  : docs/07-quality/testing-and-validation.md, ADR-0011
-- Parameter  : <% database %>
--
-- Everything here is deterministic and calls no model, so it runs on every
-- `just verify` for the price of a few metadata queries. Agent ANSWER quality
-- (citations, T-39/T-40) needs a model call and lives in the evidence entry,
-- not in the gate.
--
-- DQ-AGENT-READ-ONLY is the one that matters. It reads the tool list from the
-- LIVE agent (DESCRIBE AGENT), not from the SQL file, so a hand-edited agent in
-- Snowsight is caught too. Any tool type outside the two read-only ones fails.
--
-- DQ-DOC-DATA-CONSISTENT exists because the agent answers from two sources at
-- once. If a document cites a part number or alarm code the data does not
-- have, the agent will put a confident contradiction in one answer.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-AGENT-READ-ONLY',     'T-48', 'G4', 'The live agent has only read-only tools',
            'An agent that can call a write procedure and so route around approval', true),
        ('DQ-AGENT-REACHABLE',     'T-84', 'G4', 'RMC and planning users can open the agent in Snowflake Intelligence',
         'An agent that exists but that nobody it was built for can reach', true),
        ('DQ-SV-DESCRIBED',        'T-42', 'G5', 'Every semantic-view table, fact, dimension and metric has a description',
            'Cortex Analyst guessing what a column means', false),
        ('DQ-SV-SAMPLES-REAL',     'T-42', 'G5', 'Every example value quoted in a description exists in the data',
            'A description that teaches Analyst an identifier that does not exist', false),
        ('DQ-DOC-SECTIONS',        'T-37', 'G5', 'Every parsed document keeps at least two named sections',
            'A citation that cannot be opened to a section', false),
        ('DQ-DOC-DATA-CONSISTENT', 'T-37', 'G5', 'Every part number and alarm code a document cites exists in the data',
            'An answer whose document half contradicts its data half', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_G3_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id varchar;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    -- T-48: read the live spec. Allowed types are the two read-only ones.
    describe agent GEN.WOA_OPS_AGENT;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-AGENT-READ-ONLY', 'T-48', current_timestamp()::timestamp_ntz,
           n_bad = 0 and n_tools > 0, n_bad, 0,
           n_tools || ' tools; ' || n_bad || ' outside {cortex_analyst_text_to_sql, cortex_search}'
           || coalesce(': ' || bad_list, '')
    from (
        select count(*) as n_tools,
               count_if(t.value:tool_spec:type::varchar not in ('cortex_analyst_text_to_sql', 'cortex_search')) as n_bad,
               listagg(case when t.value:tool_spec:type::varchar not in ('cortex_analyst_text_to_sql', 'cortex_search')
                            then t.value:tool_spec:name::varchar || '(' || t.value:tool_spec:type::varchar || ')' end, ', ') as bad_list
        from table(result_scan(last_query_id())) d,
             lateral flatten(input => parse_json(d."agent_spec"):tools) t
    );

    -- T-42a: every described object has a non-trivial COMMENT.
    describe semantic view SERVING.SV_WIND_OPS;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-SV-DESCRIBED', 'T-42', current_timestamp()::timestamp_ntz,
           n_missing = 0, n_missing, 0,
           n_objects || ' tables/facts/dimensions/metrics; ' || n_missing || ' without a description'
           || coalesce(': ' || missing_list, '')
    from (
        select count(*) as n_objects,
               count_if(c is null or length(c) < 10) as n_missing,
               listagg(case when c is null or length(c) < 10 then kind || ' ' || name end, ', ') as missing_list
        from (
            select "object_kind" as kind, "object_name" as name,
                   max(case when "property" = 'COMMENT' then "property_value" end) as c
            from table(result_scan(last_query_id()))
            where "object_kind" in ('TABLE', 'FACT', 'DIMENSION', 'METRIC')
            group by 1, 2
        )
    );

    -- T-42b: the example values the descriptions quote are real.
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-SV-SAMPLES-REAL', 'T-42', current_timestamp()::timestamp_ntz,
           n_missing = 0, n_missing, 0,
           n_missing || ' of 5 quoted examples (KA-CTD, GJ-KCH, TN-TVL, KA-CTD-T07, SA-OT-004) missing from the data'
    from (
        select 5 - (
              (select count(*) from RAW.DIM_SITE where site_code in ('KA-CTD', 'GJ-KCH', 'TN-TVL'))
            + (select count(*) from RAW.DIM_TURBINE where turbine_id = 'KA-CTD-T07')
            + (select count(*) from RAW.DIM_ALARM_CODE where alarm_code = 'SA-OT-004')
        ) as n_missing
    );

    -- T-37: each document has at least two named (non-preamble) sections.
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-DOC-SECTIONS', 'T-37', current_timestamp()::timestamp_ntz,
           n_docs > 0 and n_thin = 0, n_thin, 0,
           n_docs || ' documents parsed; ' || n_thin || ' with fewer than two named sections'
    from (
        select count(*) as n_docs, count_if(n_sections < 2) as n_thin
        from (
            select p.doc_id, count(distinct case when c.section <> 'Preamble' then c.section end) as n_sections
            from DOCS.DOC_PARSED p
            left join DOCS.DOC_CHUNK c on c.doc_id = p.doc_id
            group by 1
        )
    );

    -- Consistency: part numbers and alarm codes cited in documents exist in RAW.
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-DOC-DATA-CONSISTENT', 'T-37', current_timestamp()::timestamp_ntz,
           n_cited > 0 and n_unknown = 0, n_unknown, 0,
           n_cited || ' distinct codes cited; ' || n_unknown || ' not in RAW' || coalesce(': ' || unknown_list, '')
    from (
        select count(*) as n_cited,
               count_if(not known) as n_unknown,
               listagg(case when not known then code end, ', ') as unknown_list
        from (
            select distinct f.value::varchar as code,
                   f.value::varchar in (select part_number from RAW.DIM_PART
                                        union all select alarm_code from RAW.DIM_ALARM_CODE) as known
            from DOCS.DOC_CHUNK c,
                 lateral flatten(input => regexp_substr_all(c.chunk_text,
                     'PT-[A-Z]{3}-[A-Z]+(-[A-Z]+)*|(SA|CM)-[A-Z]{2}-[0-9]{3}')) f
        )
    );

    -- T-84: the agent is reachable by the people it is for (FR-86). Three
    -- links, each of which silently hides it when missing: the Snowflake
    -- Intelligence list, USAGE on the agent, and WOA_APP inheriting WOA_AGENT.
    let listed integer := 0;
    let usage_ok integer := 0;
    let inherits integer := 0;
    show agents in snowflake intelligence SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
    listed := (select count(*) from table(result_scan(last_query_id()))
               where "database_name" = current_database() and "schema_name" = 'GEN'
                 and "name" = 'WOA_OPS_AGENT');
    show grants on agent GEN.WOA_OPS_AGENT;
    usage_ok := (select count(*) from table(result_scan(last_query_id()))
                 where "privilege" = 'USAGE' and "grantee_name" = 'WOA_AGENT');
    show grants to role WOA_APP;
    inherits := (select count(*) from table(result_scan(last_query_id()))
                 where "granted_on" = 'ROLE' and "name" = 'WOA_AGENT');
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-AGENT-REACHABLE', 'T-84', current_timestamp()::timestamp_ntz,
           :listed > 0 and :usage_ok > 0 and :inherits > 0,
           iff(:listed > 0, 0, 1) + iff(:usage_ok > 0, 0, 1) + iff(:inherits > 0, 0, 1), 0,
           'listed in Snowflake Intelligence: ' || iff(:listed > 0, 'yes', 'NO')
           || '; USAGE to WOA_AGENT: ' || iff(:usage_ok > 0, 'yes', 'NO')
           || '; WOA_APP inherits WOA_AGENT: ' || iff(:inherits > 0, 'yes', 'NO');

    return 'G3 quality run ' || :run_id || ' complete';
end;
$$;
