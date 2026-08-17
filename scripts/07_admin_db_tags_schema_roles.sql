-- ============================================================================
-- RBAC FRAMEWORK: Step 7 - TAGS Schema Roles (TAGS_R, TAGS_RW, TAGS_RWC)
-- ============================================================================
-- Purpose: Creates database roles scoped to the TAGS schema within ADMIN_DB.
--          Future grants ensure any new objects automatically inherit the
--          correct privilege set.
--
-- Hierarchy:  TAGS_RWC → TAGS_RW → TAGS_R → DB_R
-- Grants:
--   TAGS_R   : USAGE on schema, future SELECT on tables & views
--   TAGS_RW  : future INSERT, UPDATE, DELETE, TRUNCATE on tables
--   TAGS_RWC : future CREATE TABLE, VIEW, PROCEDURE, FUNCTION, STAGE on schema
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;

-- --------------------------------------------------------------------------
-- Create database roles
-- --------------------------------------------------------------------------
create database role if not exists TAGS_R
comment = 'Read-only access to the TAGS schema.'
;

create database role if not exists TAGS_RW
comment = 'Read-write access to the TAGS schema.'
;

create database role if not exists TAGS_RWC
comment = 'Read-write-create access to the TAGS schema.'
;

-- --------------------------------------------------------------------------
-- Static grants
-- --------------------------------------------------------------------------
grant usage on schema ADMIN_DB.TAGS to database role TAGS_R;

-- --------------------------------------------------------------------------
-- Future grants - READ
-- --------------------------------------------------------------------------
grant select on future tables in schema ADMIN_DB.TAGS to database role TAGS_R;
grant select on future views in schema ADMIN_DB.TAGS to database role TAGS_R;

-- --------------------------------------------------------------------------
-- Future grants - WRITE
-- --------------------------------------------------------------------------
grant insert on future tables in schema ADMIN_DB.TAGS to database role TAGS_RW;
grant update on future tables in schema ADMIN_DB.TAGS to database role TAGS_RW;
grant delete on future tables in schema ADMIN_DB.TAGS to database role TAGS_RW;
grant truncate on future tables in schema ADMIN_DB.TAGS to database role TAGS_RW;

-- --------------------------------------------------------------------------
-- Future grants - CREATE
-- --------------------------------------------------------------------------
grant create table on schema ADMIN_DB.TAGS to database role TAGS_RWC;
grant create view on schema ADMIN_DB.TAGS to database role TAGS_RWC;
grant create procedure on schema ADMIN_DB.TAGS to database role TAGS_RWC;
grant create function on schema ADMIN_DB.TAGS to database role TAGS_RWC;
grant create stage on schema ADMIN_DB.TAGS to database role TAGS_RWC;

-- --------------------------------------------------------------------------
-- Future grants - USAGE on procedures/functions for RW+
-- --------------------------------------------------------------------------
grant usage on future procedures in schema ADMIN_DB.TAGS to database role TAGS_RW;
grant usage on future functions in schema ADMIN_DB.TAGS to database role TAGS_RW;

-- --------------------------------------------------------------------------
-- Role hierarchy (RWC → RW → R) and roll-up to DB-level roles
-- --------------------------------------------------------------------------
grant database role TAGS_R to database role TAGS_RW;
grant database role TAGS_RW to database role TAGS_RWC;
grant database role TAGS_R to database role DB_R;
grant database role TAGS_RW to database role DB_RW;
grant database role TAGS_RWC to database role DB_RWC;
