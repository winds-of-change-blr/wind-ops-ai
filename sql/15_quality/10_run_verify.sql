-- =============================================================================
-- 15_quality / 10 — run the assertions and gate on them        STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the body of `just verify` (the G1 half)
-- Parameter  : <% database %>
--
-- Two statements, in this order, and the order matters: run the suite, then gate
-- on its result. The gate RAISEs, so `snow sql` exits non-zero and the recipe
-- fails — which is the entire point of a verify step.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

call OPS.SP_RUN_DATA_QUALITY();

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
