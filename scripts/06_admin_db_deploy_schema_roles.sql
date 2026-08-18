-- ============================================================================
-- RBAC FRAMEWORK: Step 6 - DEPLOY Schema Roles (DEPLOY_R, DEPLOY_RW, DEPLOY_RWC)
-- ============================================================================
-- Purpose: Creates database roles scoped to the DEPLOY schema within ADMIN_DB.
--          Future grants ensure any new objects automatically inherit the
--          correct privilege set.
--
-- Hierarchy:  DEPLOY_RWC → DEPLOY_RW → DEPLOY_R → DB_R
-- Grants:
--   DEPLOY_R   : USAGE on schema, future SELECT on tables & views
--   DEPLOY_RW  : future INSERT, UPDATE, DELETE, TRUNCATE on tables
--   DEPLOY_RWC : future CREATE TABLE, VIEW, PROCEDURE, FUNCTION, STAGE on schema
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;

-- --------------------------------------------------------------------------
-- Create database roles
-- --------------------------------------------------------------------------
create database role if not exists DEPLOY_R
comment = 'Read-only access to the DEPLOY schema.'
;

create database role if not exists DEPLOY_RW
comment = 'Read-write access to the DEPLOY schema.'
;

create database role if not exists DEPLOY_RWC
comment = 'Read-write-create access to the DEPLOY schema.'
;

-- --------------------------------------------------------------------------
-- Static grants
-- --------------------------------------------------------------------------
grant usage on schema ADMIN_DB.DEPLOY to database role DEPLOY_R;

-- --------------------------------------------------------------------------
-- Future grants - READ
-- --------------------------------------------------------------------------
grant select on future tables in schema ADMIN_DB.DEPLOY to database role DEPLOY_R;
grant select on future views in schema ADMIN_DB.DEPLOY to database role DEPLOY_R;

-- --------------------------------------------------------------------------
-- Future grants - WRITE
-- --------------------------------------------------------------------------
grant insert on future tables in schema ADMIN_DB.DEPLOY to database role DEPLOY_RW;
grant update on future tables in schema ADMIN_DB.DEPLOY to database role DEPLOY_RW;
grant delete on future tables in schema ADMIN_DB.DEPLOY to database role DEPLOY_RW;
grant truncate on future tables in schema ADMIN_DB.DEPLOY to database role DEPLOY_RW;

-- --------------------------------------------------------------------------
-- Future grants - CREATE
-- --------------------------------------------------------------------------
grant create table on schema ADMIN_DB.DEPLOY to database role DEPLOY_RWC;
grant create view on schema ADMIN_DB.DEPLOY to database role DEPLOY_RWC;
grant create procedure on schema ADMIN_DB.DEPLOY to database role DEPLOY_RWC;
grant create function on schema ADMIN_DB.DEPLOY to database role DEPLOY_RWC;
grant create stage on schema ADMIN_DB.DEPLOY to database role DEPLOY_RWC;

-- --------------------------------------------------------------------------
-- Future grants - USAGE on procedures/functions for RW+
-- --------------------------------------------------------------------------
grant usage on future procedures in schema ADMIN_DB.DEPLOY to database role DEPLOY_RW;
grant usage on future functions in schema ADMIN_DB.DEPLOY to database role DEPLOY_RW;

-- --------------------------------------------------------------------------
-- Role hierarchy (RWC → RW → R) and roll-up to DB-level roles
-- --------------------------------------------------------------------------
grant database role DEPLOY_R to database role DEPLOY_RW;
grant database role DEPLOY_RW to database role DEPLOY_RWC;
grant database role DEPLOY_R to database role DB_R;
grant database role DEPLOY_RW to database role DB_RW;
grant database role DEPLOY_RWC to database role DB_RWC;
