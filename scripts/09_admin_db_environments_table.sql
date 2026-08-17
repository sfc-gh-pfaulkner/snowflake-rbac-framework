-- ============================================================================
-- RBAC FRAMEWORK: Step 9 - ENVIRONMENTS Lookup Table
-- ============================================================================
-- Purpose: Defines the allowed environments for the RBAC framework.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create table if not exists ENVIRONMENTS (
    ENVIRONMENT VARCHAR not null,
    DESCRIPTION VARCHAR,
    constraint PK_ENVIRONMENTS primary key (ENVIRONMENT)
)
comment = 'Allowed environments for the RBAC framework.'
;
