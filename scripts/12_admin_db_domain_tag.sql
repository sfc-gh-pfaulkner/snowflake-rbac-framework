-- ============================================================================
-- RBAC FRAMEWORK: Step 12 - DOMAIN Tag
-- ============================================================================
-- Purpose: Creates a governance tag to classify objects by business domain.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema TAGS;
use warehouse ADMIN_WH;

create tag if not exists DOMAIN
comment = 'Classifies objects by business domain (e.g. FINANCE, IT, RESEARCH).'
;
