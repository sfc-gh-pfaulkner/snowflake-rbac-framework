-- ============================================================================
-- RBAC FRAMEWORK: Step 11 - ENVIRONMENT Tag
-- ============================================================================
-- Purpose: Creates a governance tag to classify objects by environment.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema TAGS;
use warehouse ADMIN_WH;

create tag if not exists ENVIRONMENT
comment = 'Classifies objects by deployment environment (e.g. PRD, DEV).'
;
