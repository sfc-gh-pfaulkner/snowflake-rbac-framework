-- ============================================================================
-- RBAC FRAMEWORK: Step 1 - DEPLOYMENT_ADMIN Role
-- ============================================================================
-- Purpose: Creates the DEPLOYMENT_ADMIN account role used to execute all
--          subsequent RBAC deployment scripts. This role has the minimum
--          privileges needed to build out the environment framework:
--          CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE.
--
-- Ownership: SECURITYADMIN (so it sits within the security hierarchy)
-- Inheritance: Granted to ACCOUNTADMIN (so ACCOUNTADMIN inherits its privileges)
-- ============================================================================

CREATE ROLE IF NOT EXISTS DEPLOYMENT_ADMIN
    COMMENT = 'Deploys RBAC framework objects: databases, warehouses, and roles.';

-- Grant infrastructure-creation privileges
GRANT CREATE DATABASE  ON ACCOUNT TO ROLE DEPLOYMENT_ADMIN;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE DEPLOYMENT_ADMIN;
GRANT CREATE ROLE      ON ACCOUNT TO ROLE DEPLOYMENT_ADMIN;
GRANT CREATE USER      ON ACCOUNT TO ROLE DEPLOYMENT_ADMIN;

-- Roll up into ACCOUNTADMIN so the hierarchy remains intact
GRANT ROLE DEPLOYMENT_ADMIN TO ROLE ACCOUNTADMIN;

-- --------------------------------------------------------------------------
-- Grant MANAGE GRANTS to DEPLOYMENT_ADMIN (required for ownership transfers)
-- --------------------------------------------------------------------------

GRANT MANAGE GRANTS ON ACCOUNT TO ROLE DEPLOYMENT_ADMIN;

-- Add DEPLOYMENT_ADMIN to the blocked secondary roles policy (now that it exists)
ALTER SESSION POLICY GOVERNANCE_DB.POLICIES.BLOCK_PRIVILEGED_SECONDARY_ROLES SET
    BLOCKED_SECONDARY_ROLES = (ACCOUNTADMIN, SECURITYADMIN, USERADMIN, SYSADMIN, DEPLOYMENT_ADMIN);
