-- =============================================================================
-- 60_docs / 02 — Cortex Search over the maintenance documents   STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-29 (indexed in a search service), the agent's document tool
-- Proves     : T-38 (a newly staged document becomes findable within the lag)
-- Authority  : ADR-0010, CMP-11
-- Parameter  : <% database %>
--
-- Indexes DOCS.DOC_CHUNK, the SECTION-level chunks 01_documents.sql builds. The
-- search-optimization skill's own pipeline was not used: it re-parses into
-- fixed 500-character chunks, which would cut sections in half and lose the
-- headings a citation needs (T-37). Deviation recorded in STATE.md §7.
--
-- The attributes are what a citation is made of: doc_id + section is the
-- human-resolvable reference ("VWS-MP-GBX-014 · 4. Procedure").
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace cortex search service DOCS.CSS_MAINTENANCE_DOCS
    on chunk_text
    attributes doc_id, doc_title, section, file_name
    warehouse = WOA_BUILD_WH
    target_lag = '1 day'
    comment = 'Search over synthetic maintenance procedures and policies, one row per document section. SYNTHETIC — fictional OEM.'
as
    select chunk_text, doc_id, doc_title, section, file_name, chunk_id
    from DOCS.DOC_CHUNK;
