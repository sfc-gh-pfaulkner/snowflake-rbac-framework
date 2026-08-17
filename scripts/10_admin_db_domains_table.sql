-- ============================================================================
-- RBAC FRAMEWORK: Step 10 - DOMAINS Lookup Table
-- ============================================================================
-- Purpose: Defines the allowed business domains for the RBAC framework.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create table if not exists DOMAINS (
    DOMAIN VARCHAR not null,
    DESCRIPTION VARCHAR,
    constraint PK_DOMAINS primary key (DOMAIN)
)
comment = 'Allowed business domains for the RBAC framework.'
;
