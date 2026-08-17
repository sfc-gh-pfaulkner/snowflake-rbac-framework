-- ============================================================================
-- RBAC FRAMEWORK: Step 3 - DEPLOY Schema (Managed Access)
-- ============================================================================
-- Purpose: Creates the DEPLOY schema within ADMIN_DB. This schema will hold
--          stored procedures that drive the RBAC framework deployments.
--          MANAGED ACCESS ensures only the schema owner can grant privileges.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;

create schema if not exists DEPLOY
with managed access
comment = 'Deployment stored procedures for RBAC framework provisioning.'
;

create schema if not exists DCM
with managed access
comment = 'DCM projects managed by the domain code repo.'
;

drop schema if exists ADMIN_DB.PUBLIC;

-- Create DCM project for functional roles
create dcm project if not exists ADMIN_DB.DCM.FUNCTIONAL_ROLES;
