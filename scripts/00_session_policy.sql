-- ============================================================================
-- RBAC FRAMEWORK: Step 0 - Account Session Policy
-- ============================================================================
-- Purpose: Blocks privileged admin roles from being activated as secondary
--          roles.  By default Snowflake activates all granted roles as
--          secondary roles (BCR-1692).  This policy ensures that users must
--          explicitly USE ROLE to exercise elevated privileges.
--
-- Prerequisite: None (first script to run)
-- ============================================================================

-- Run as ACCOUNTADMIN (pass --role ACCOUNTADMIN on the CLI)

CREATE DATABASE IF NOT EXISTS GOVERNANCE_DB
    COMMENT = 'Account-level security policies and controls.';
DROP SCHEMA IF EXISTS GOVERNANCE_DB.PUBLIC;
CREATE SCHEMA IF NOT EXISTS GOVERNANCE_DB.POLICIES;

CREATE SESSION POLICY IF NOT EXISTS GOVERNANCE_DB.POLICIES.BLOCK_PRIVILEGED_SECONDARY_ROLES
    BLOCKED_SECONDARY_ROLES = (ACCOUNTADMIN, SECURITYADMIN, USERADMIN, SYSADMIN)
    COMMENT = 'Prevents privileged roles from being activated as secondary roles.';

ALTER SESSION POLICY GOVERNANCE_DB.POLICIES.BLOCK_PRIVILEGED_SECONDARY_ROLES SET
    BLOCKED_SECONDARY_ROLES = (ACCOUNTADMIN, SECURITYADMIN, USERADMIN, SYSADMIN);

ALTER ACCOUNT SET SESSION POLICY GOVERNANCE_DB.POLICIES.BLOCK_PRIVILEGED_SECONDARY_ROLES FORCE;
