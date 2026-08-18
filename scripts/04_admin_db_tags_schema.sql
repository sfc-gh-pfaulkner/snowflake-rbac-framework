-- ============================================================================
-- RBAC FRAMEWORK: Step 4 - TAGS Schema (Managed Access)
-- ============================================================================
-- Purpose: Creates the TAGS schema within ADMIN_DB. This schema will hold
--          object and column tags used for governance and classification.
--          MANAGED ACCESS ensures only the schema owner can grant privileges.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;

create schema if not exists TAGS
with managed access
comment = 'Tag definitions for data governance and classification.'
;
