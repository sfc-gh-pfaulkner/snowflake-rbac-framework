-- ============================================================================
-- RBAC FRAMEWORK: Step 19 - DEPLOY_CLONE Procedure (unified WIP/TEST/UAT/PREPROD/SAFE)
-- ============================================================================
-- Purpose: Clones an RBAC-managed database for development or promotion.
--          Creates a developer role (if not exists) and grants access based on
--          clone type.
--
--          Idempotent: drops an existing clone of the same name before
--          re-creating, uses CREATE ROLE IF NOT EXISTS.
--
-- Caller:  Must be called as the domain SYSADMIN (e.g. DEV_HR_SYSADMIN)
-- Params:  ISSUE_ID         - GitHub Issue identifier (e.g. '1', '42')
--          ENVIRONMENT_NAME - source environment (e.g. 'DEV')
--          DOMAIN_NAME      - registered domain (e.g. 'HR')
--          DB_NAME          - logical database name (e.g. 'CORE')
--          CLONE_TYPE       - 'WIP', 'TEST', 'UAT', 'PREPROD', or 'SAFE'
--
-- Derived names:
--   Source database : <ENVIRONMENT>_<DOMAIN>_<DB_NAME>_DB
--   Clone database  : <CLONE_TYPE>_<ISSUE_ID>_<DOMAIN>_<DB_NAME>_DB
--   Developer role  : <ENVIRONMENT>_<DOMAIN>_DEVELOPER
--   Dev warehouse   : <DOMAIN>_DEV_WH
--
-- Access model:
--   WIP     -> developer role gets DB_RWC (full read/write/create)
--   TEST    -> ANALYST, MANAGER, DATASTEWARD, POWERBI roles get DB_R (read-only)
--   UAT     -> ANALYST, MANAGER, DATASTEWARD, POWERBI roles get DB_R (read-only)
--   PREPROD -> MANAGER role only gets DB_R (read-only)
--   SAFE    -> no role access (rollback snapshot, owned by DEPLOYMENT_ADMIN)
--
-- Architecture:
--   _PROVISION_CLONE (EXECUTE AS OWNER / DEPLOYMENT_ADMIN)
--     - Drops/creates the clone database (requires CREATE DATABASE)
--     - Creates the developer role (requires CREATE ROLE)
--     - Grants database role and warehouse access (requires MANAGE GRANTS)
--   DEPLOY_CLONE (EXECUTE AS CALLER / domain SYSADMIN)
--     - Validates caller, calls the helper
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

-- --------------------------------------------------------------------------
-- Helper: _PROVISION_CLONE (elevated privileges via DEPLOYMENT_ADMIN)
-- --------------------------------------------------------------------------
create or replace procedure ADMIN_DB.DEPLOY._PROVISION_CLONE(
    ISSUE_ID VARCHAR,
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    DB_NAME VARCHAR,
    CLONE_TYPE VARCHAR
)
returns VARCHAR
language sql
comment = 'Internal helper: clones a database and provisions role access. Requires DEPLOYMENT_ADMIN privileges.'
execute as owner
as
$$
begin
    -- Validate CLONE_TYPE
    if (upper(:CLONE_TYPE) not in ('WIP', 'TEST', 'UAT', 'PREPROD', 'SAFE')) then
        return 'ERROR: CLONE_TYPE must be WIP, TEST, UAT, PREPROD, or SAFE.';
    end if;

    -- Construct names
    let clone_type_upper VARCHAR := upper(:CLONE_TYPE);
    let domain_sysadmin  VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_SYSADMIN';
    let source_db        VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';
    let clone_db         VARCHAR := :clone_type_upper || '_' || :ISSUE_ID || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';
    let dev_role         VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_DEVELOPER';
    let dev_wh           VARCHAR := :DOMAIN_NAME || '_DEV_WH';

    -- Drop existing clone (idempotent)
    execute immediate 'drop database if exists identifier(:1)' using (clone_db);

    -- Clone the source database
    execute immediate 'create database identifier(:1) CLONE identifier(:2)' using (clone_db, source_db);

    -- Create DCM project in the clone (grants applied later after ownership transfer)
    let dcm_project VARCHAR := :clone_db || '.DCM.' || :DOMAIN_NAME || '_' || :DB_NAME || '_PROJECT';
    begin
        execute immediate 'create dcm project if not exists identifier(:1)' using (dcm_project);
    exception
        when other then null; -- DCM schema may not exist in older databases
    end;

    -- SAFE clones: no grants, no ownership transfer — stays with DEPLOYMENT_ADMIN as a read-only snapshot
    if (:clone_type_upper = 'SAFE') then
        return 'OK';
    end if;

    -- Take ownership of all schemas (copy grants to preserve DB_R/DB_RW access)
    execute immediate 'grant ownership on all SCHEMAS in database identifier(:1) to role DEPLOYMENT_ADMIN COPY current grants' using (clone_db);

    -- Make DB_RWC subordinate to DEPLOYMENT_ADMIN (required for ownership transfer)
    let db_rwc_role VARCHAR := :clone_db || '.DB_RWC';
    execute immediate 'grant database role identifier(:1) to role DEPLOYMENT_ADMIN' using (db_rwc_role);

    -- Create DEVELOPER role and grant warehouse (WIP clones only — DEV_WH doesn't exist in PROD)
    if (:clone_type_upper = 'WIP') then
        execute immediate 'create role if not exists identifier(:1)' using (dev_role);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (dev_role, domain_sysadmin);
        execute immediate 'grant usage on warehouse identifier(:1) to role identifier(:2)' using (dev_wh, dev_role);
        execute immediate 'grant operate on warehouse identifier(:1) to role identifier(:2)' using (dev_wh, dev_role);
    end if;

    -- Grant access based on clone type
    if (:clone_type_upper = 'WIP') then
        -- WIP: DEVELOPER gets full read/write/create
        execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (clone_db, dev_role);
        let DB_RWC VARCHAR := :clone_db || '.DB_RWC';
        execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (DB_RWC, dev_role);

        -- Also grant read-only on source for comparison
        execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (source_db, dev_role);
        let source_db_r VARCHAR := :source_db || '.DB_R';
        execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (source_db_r, dev_role);

    elseif (:clone_type_upper in ('TEST', 'UAT')) then
        -- TEST/UAT: ANALYST, MANAGER, DATASTEWARD, POWERBI get read-only
        let DB_R VARCHAR := :clone_db || '.DB_R';
        let role_analyst    VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_ANALYST';
        let role_manager    VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_MANAGER';
        let role_datasteward VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_DATASTEWARD';
        let role_powerbi    VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_POWERBI';

        begin
            execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (clone_db, role_analyst);
            execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (DB_R, role_analyst);
        exception when OTHER then NULL;
        end;
        begin
            execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (clone_db, role_manager);
            execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (DB_R, role_manager);
        exception when OTHER then NULL;
        end;
        begin
            execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (clone_db, role_datasteward);
            execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (DB_R, role_datasteward);
        exception when OTHER then NULL;
        end;
        begin
            execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (clone_db, role_powerbi);
            execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (DB_R, role_powerbi);
        exception when OTHER then NULL;
        end;

    elseif (:clone_type_upper = 'PREPROD') then
        -- PREPROD: MANAGER only gets read-only
        let DB_R VARCHAR := :clone_db || '.DB_R';
        let role_manager VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_MANAGER';

        begin
            execute immediate 'grant usage on database identifier(:1) to role identifier(:2)' using (clone_db, role_manager);
            execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (DB_R, role_manager);
        exception when OTHER then NULL;
        end;
    end if;

    -- -----------------------------------------------------------------------
    -- Iterate schemas: revoke future grants, transfer ownership to _RWC
    -- -----------------------------------------------------------------------
    let schema_query VARCHAR := 'select SCHEMA_NAME from ' || :clone_db || '.INFORMATION_SCHEMA.SCHEMATA where SCHEMA_NAME not in (''INFORMATION_SCHEMA'', ''DCM'')';
    let schema_rs RESULTSET := (execute immediate :schema_query);
    let schema_cursor cursor for schema_rs;

    for schema_rec in schema_cursor do
        let sn VARCHAR := schema_rec.SCHEMA_NAME;
        let fs VARCHAR := :clone_db || '.' || :sn;
        let rwc VARCHAR := :clone_db || '.' || :sn || '_RWC';

        -- Transfer ownership (managed access stays on — works because _RWC is subordinate)
        -- Future grants are preserved so _R and _RW roles see newly created objects
        execute immediate 'grant ownership on all tables in schema ' || :fs || ' to database role ' || :rwc || ' copy current grants';
        execute immediate 'grant ownership on all views in schema ' || :fs || ' to database role ' || :rwc || ' copy current grants';
        execute immediate 'grant ownership on all dynamic tables in schema ' || :fs || ' to database role ' || :rwc || ' copy current grants';
        execute immediate 'grant ownership on schema ' || :fs || ' to database role ' || :rwc || ' copy current grants';
    end for;

    -- Grant DCM access for deployments
    -- WIP clones: DEVELOPER deploys interactively
    -- TEST/UAT/PREPROD clones: domain SYSADMIN deploys via CI/CD
    let dcm_deploy_role VARCHAR;
    if (:clone_type_upper = 'WIP') then
        dcm_deploy_role := :dev_role;
    else
        dcm_deploy_role := :domain_sysadmin;
    end if;

    begin
        execute immediate 'grant usage on schema ' || :clone_db || '.DCM to role ' || :dcm_deploy_role;
        execute immediate 'grant ownership on dcm project ' || :dcm_project || ' to role ' || :dcm_deploy_role || ' copy current grants';
    exception
        when other then null;
    end;

    -- Transfer database ownership to DOMAIN SYSADMIN (last step)
    execute immediate 'grant ownership on database identifier(:1) to role identifier(:2) copy current grants' using (clone_db, domain_sysadmin);

    return 'OK';
end;
$$
;

-- --------------------------------------------------------------------------
-- Main: DEPLOY_CLONE (runs as domain SYSADMIN caller)
-- --------------------------------------------------------------------------
create or replace procedure ADMIN_DB.DEPLOY.DEPLOY_CLONE(
    ISSUE_ID VARCHAR,
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    DB_NAME VARCHAR,
    CLONE_TYPE VARCHAR
)
returns VARCHAR
language sql
comment = 'Clones a database for WIP, TEST, UAT, or PREPROD use. Must be called as the domain SYSADMIN.'
execute as caller
as
$$
begin
    -- Validate CLONE_TYPE
    if (upper(:CLONE_TYPE) not in ('WIP', 'TEST', 'UAT', 'PREPROD', 'SAFE')) then
        return 'ERROR: CLONE_TYPE must be WIP, TEST, UAT, PREPROD, or SAFE.';
    end if;

    -- Validate caller is the DOMAIN SYSADMIN or DEVELOPER
    let domain_sysadmin VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_SYSADMIN';
    let domain_developer VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_DEVELOPER';

    if (current_role() != :domain_sysadmin and current_role() != :domain_developer) then
        return 'ERROR: Must be called as ' || :domain_sysadmin || ' or ' || :domain_developer || '. Current role: ' || current_role();
    end if;

    -- Delegate all work to the OWNER proc
    let result VARCHAR;
    CALL ADMIN_DB.DEPLOY._PROVISION_CLONE(:ISSUE_ID, :ENVIRONMENT_NAME, :DOMAIN_NAME, :DB_NAME, :CLONE_TYPE) into :result;

    if (:result != 'OK') then
        return :result;
    end if;

    -- If creating a WIP clone, also create a SAFE snapshot automatically
    let clone_type_upper VARCHAR := upper(:CLONE_TYPE);
    if (:clone_type_upper = 'WIP') then
        let safe_result VARCHAR;
        CALL ADMIN_DB.DEPLOY._PROVISION_CLONE(:ISSUE_ID, :ENVIRONMENT_NAME, :DOMAIN_NAME, :DB_NAME, 'SAFE') into :safe_result;
    end if;
    let clone_db VARCHAR := :clone_type_upper || '_' || :ISSUE_ID || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';
    let source_db VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';

    let access_desc VARCHAR;
    case :clone_type_upper
        when 'WIP' then access_desc := 'DEVELOPER role has full RWC access. SAFE snapshot also created.';
        when 'TEST' then access_desc := 'ANALYST, MANAGER, DATASTEWARD, POWERBI roles have read-only access';
        when 'UAT' then access_desc := 'ANALYST, MANAGER, DATASTEWARD, POWERBI roles have read-only access';
        when 'PREPROD' then access_desc := 'MANAGER role has read-only access';
        when 'SAFE' then access_desc := 'No role access (rollback snapshot)';
    end case;

    return 'SUCCESS: ' || :clone_type_upper || ' clone "' || :clone_db || '" created from "' || :source_db || '". ' || :access_desc || '.';
end;
$$
;

-- --------------------------------------------------------------------------
-- Re-grant USAGE on clone procedures to all domain SYSADMIN and DEVELOPER roles
-- --------------------------------------------------------------------------
execute immediate $$
declare
    grant_sql VARCHAR;
    c1 cursor for
        select "name" as ROLE_NAME from table(result_scan(last_query_id()))
        where "name" ILIKE '%\\_%\\_SYSADMIN' ESCAPE '\\'
           or "name" ILIKE '%\\_%\\_DEVELOPER' ESCAPE '\\';
begin
    SHOW ROLES in ACCOUNT;
    open c1;
    for rec in c1 do
        grant_sql := 'grant usage on procedure ADMIN_DB.DEPLOY.DEPLOY_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || rec.ROLE_NAME;
        execute immediate :grant_sql;
        grant_sql := 'grant usage on procedure ADMIN_DB.DEPLOY._PROVISION_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || rec.ROLE_NAME;
        execute immediate :grant_sql;
    end for;
    return 'Grants applied';
end;
$$;
