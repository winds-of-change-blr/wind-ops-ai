-- =============================================================================
-- 15_quality / 12 — run and gate the engine assertions            STAGE: WOA_ADMIN
-- =============================================================================
use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

call OPS.SP_RUN_ENGINE_QUALITY();

select
    test_id,
    assertion_id,
    case when passed then 'PASS' else 'FAIL' end as verdict,
    measured_value,
    threshold_value,
    detail
from OPS.DQ_RESULT
where run_id = (select max(run_id) from OPS.DQ_RESULT)
order by passed, test_id, assertion_id;

call OPS.SP_ASSERT_QUALITY_GATE();
