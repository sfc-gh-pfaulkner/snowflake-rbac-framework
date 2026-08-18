-- ============================================================================
-- RBAC FRAMEWORK: Step 2 - ADMIN_DB Database
-- ============================================================================
-- Purpose: Creates the ADMIN_DB database used to house deployment procedures,
--          tag definitions, and framework utilities.
-- ============================================================================

use role DEPLOYMENT_ADMIN;

create database if not exists ADMIN_DB
comment = 'RBAC framework administration database. Houses deployment procs and tag definitions.'
;
