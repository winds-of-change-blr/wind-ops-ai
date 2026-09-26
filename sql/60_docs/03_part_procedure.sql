-- =============================================================================
-- 60_docs / 03 — which procedure applies to which part            STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-34 (a draft carries its procedure reference)
-- Proves     : DQ-DRAFT-PROCEDURE-RESOLVES (every part maps to a parsed document)
-- Parameter  : <% database %>
--
-- A work-order draft must cite the procedure a technician will follow. That is
-- a fact about the document library, so it is held here as data, not inferred
-- by a model at draft time. Every row is asserted to point at a document that
-- was actually parsed, so a draft cannot cite a document that does not exist.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace table DOCS.DOC_PART_PROCEDURE (
    part_number   varchar(40) not null,
    doc_id        varchar(40) not null,
    section       varchar(300),
    is_synthetic  boolean     not null default true,
    constraint pk_doc_part_procedure primary key (part_number)
) comment = 'Which maintenance procedure applies to each part. Asserted against DOC_PARSED. SYNTHETIC.';

insert into DOCS.DOC_PART_PROCEDURE (part_number, doc_id, section)
select * from values
    ('PT-GBX-BEAR-HSS', 'VWS-MP-GBX-014', '4. Procedure'),
    ('PT-GBX-BEAR-IMS', 'VWS-MP-GBX-021', '1. Scope'),
    ('PT-GBX-FULL',     'VWS-MP-GBX-021', '1. Scope'),
    ('PT-GBX-OIL-COOL', 'VWS-SOP-CMS-002', '3. Escalation'),
    ('PT-GEN-BEAR-DE',  'VWS-MP-GEN-008', '3. Procedure'),
    ('PT-GEN-BEAR-NDE', 'VWS-MP-GEN-008', '3. Procedure'),
    ('PT-GEN-STATOR',   'VWS-MP-GEN-012', '1. Scope'),
    ('PT-MSB-BEAR',     'VWS-MP-MSB-003', '1. Scope'),
    ('PT-PIT-BAT',      'VWS-MP-PIT-011', '3. Procedure'),
    ('PT-PIT-MOTOR',    'VWS-MP-PIT-011', '3. Procedure'),
    ('PT-PIT-BEAR',     'VWS-MP-PIT-015', '1. Scope'),
    ('PT-CNV-IGBT',     'VWS-MP-CNV-006', '3. Procedure'),
    ('PT-CNV-PUMP',     'VWS-MP-CNV-006', '3. Procedure');
