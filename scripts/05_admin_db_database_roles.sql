-- ============================================================================
-- RBAC FRAMEWORK: Step 5 - Database-Level Roles (DB_R, DB_RW, DB_RWC)
-- ============================================================================
-- Purpose: Creates database roles scoped to ADMIN_DB that control access at
--          the database level. These form the top of the in-database hierarchy.
--
-- Hierarchy:  DB_RWC → DB_RW → DB_R
-- Grants:     None — privileges flow up from schema-level roles via hierarchy.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;

-- --------------------------------------------------------------------------
-- Create database roles
-- --------------------------------------------------------------------------
create database role if not exists DB_R
comment = 'Read-only access at database level.'
;

create database role if not exists DB_RW
comment = 'Read-write access at database level.'
;

create database role if not exists DB_RWC
comment = 'Read-write-create access at database level (can create schemas).'
;
