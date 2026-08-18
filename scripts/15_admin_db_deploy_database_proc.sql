-- ============================================================================
-- RBAC FRAMEWORK: Step 15 - DEPLOY_DATABASE Procedure
-- ============================================================================
-- Purpose: Creates a new database within the RBAC framework, tags it with
--          environment and domain, transfers ownership to the environment
--          SYSADMIN, and creates DB-level database roles owned by the domain
--          RBAC role.
--
-- Owner:   DEPLOYMENT_ADMIN (executes with owner's rights)
-- Params:  ENVIRONMENT_NAME - registered environment (e.g. PRD, DEV)
--          DOMAIN_NAME      - registered domain (e.g. FINANCE, IT)
--          DB_NAME          - logical database name (suffixed with _DB)
--
-- Resulting DB name: <ENVIRONMENT>_<DOMAIN>_<DB_NAME>_DB
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure ADMIN_DB.DEPLOY.DEPLOY_DATABASE(
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    DB_NAME VARCHAR
)
returns VARCHAR
language sql
comment = 'Creates a database, tags it, assigns ownership, and creates DB-level roles. Idempotent.'
execute as owner
as
$$
begin
    -- 0. Validate inputs
    if (:ENVIRONMENT_NAME IS NULL or trim(:ENVIRONMENT_NAME) = '') then
        return 'ERROR: ENVIRONMENT_NAME is required.';
    end if;
    if (:DOMAIN_NAME IS NULL or trim(:DOMAIN_NAME) = '') then
        return 'ERROR: DOMAIN_NAME is required.';
    end if;
    if (:DB_NAME IS NULL or trim(:DB_NAME) = '') then
        return 'ERROR: DB_NAME is required.';
    end if;

    -- 1. Validate caller has an appropriate role available
    let env_sysadmin_check VARCHAR := :ENVIRONMENT_NAME || '_SYSADMIN';
    let domain_sysadmin VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_SYSADMIN';

    if (not array_contains('DEPLOYMENT_ADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('SYSADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('ACCOUNTADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains(:env_sysadmin_check::VARIANT, parse_json(current_available_roles()))
        and not array_contains(:domain_sysadmin::VARIANT, parse_json(current_available_roles()))) then
        return 'ERROR: Caller must have DEPLOYMENT_ADMIN, SYSADMIN, ACCOUNTADMIN, ' || :env_sysadmin_check || ', or ' || :domain_sysadmin || ' available.';
    end if;

    -- 2. Validate ENVIRONMENT exists
    let env_exists INT := 0;
    select count(*) into :env_exists from ADMIN_DB.DEPLOY.ENVIRONMENTS where ENVIRONMENT = :ENVIRONMENT_NAME;
    if (:env_exists = 0) then
        return 'ERROR: Environment "' || :ENVIRONMENT_NAME || '" is not registered. Call DEPLOY_ENVIRONMENT first.';
    end if;

    -- 3. Validate DOMAIN exists
    let domain_exists INT := 0;
    select count(*) into :domain_exists from ADMIN_DB.DEPLOY.DOMAINS where DOMAIN = :DOMAIN_NAME;
    if (:domain_exists = 0) then
        return 'ERROR: Domain "' || :DOMAIN_NAME || '" is not registered. Call DEPLOY_DOMAIN first.';
    end if;

    -- 4. Construct full database name
    let full_db_name VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';

    -- 5. Check if database already exists (SHOW DATABASES is visible with MANAGE grants)
    let db_exists INT := 0;
    SHOW DATABASES like :full_db_name;
    let rs RESULTSET := (select count(*) as CNT from table(result_scan(last_query_id())));
    let cur cursor for rs;
    open cur;
    FETCH cur into db_exists;
    CLOSE cur;

    if (:db_exists > 0) then
        return 'SKIPPED: Database "' || :full_db_name || '" already exists.';
    end if;

    -- 6. Create the database
    execute immediate 'create database identifier(:1)' using (full_db_name);

    -- 6a. Drop the default PUBLIC schema
    let public_schema VARCHAR := :full_db_name || '.PUBLIC';
    execute immediate 'drop schema if exists identifier(:1)' using (public_schema);

    -- 7. Tag with ENVIRONMENT and DOMAIN
    execute immediate 'alter database identifier(:1) set tag ADMIN_DB.TAGS.ENVIRONMENT = :2' using (full_db_name, ENVIRONMENT_NAME);
    execute immediate 'alter database identifier(:1) set tag ADMIN_DB.TAGS.DOMAIN = :2' using (full_db_name, DOMAIN_NAME);

    -- 8. Create DB-level database roles (DB_R, DB_RW, DB_RWC)
    let db_role_r VARCHAR := :full_db_name || '.DB_R';
    let db_role_rw VARCHAR := :full_db_name || '.DB_RW';
    let db_role_rwc VARCHAR := :full_db_name || '.DB_RWC';
    execute immediate 'create database role if not exists identifier(:1)' using (db_role_r);
    execute immediate 'create database role if not exists identifier(:1)' using (db_role_rw);
    execute immediate 'create database role if not exists identifier(:1)' using (db_role_rwc);

    -- 9. Transfer ownership of database roles to DOMAIN RBAC role
    let domain_rbac VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_RBAC';
    execute immediate 'grant ownership on database role identifier(:1) to role identifier(:2) copy current grants' using (db_role_r, domain_rbac);
    execute immediate 'grant ownership on database role identifier(:1) to role identifier(:2) copy current grants' using (db_role_rw, domain_rbac);
    execute immediate 'grant ownership on database role identifier(:1) to role identifier(:2) copy current grants' using (db_role_rwc, domain_rbac);

    -- 10. Grant database roles to DOMAIN account roles
    let domain_reader VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_READER';
    let domain_etl VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_ETL';
    let domain_sysadmin_role VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_SYSADMIN';
    execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (db_role_r, domain_reader);
    execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (db_role_rw, domain_etl);
    execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (db_role_rwc, domain_sysadmin_role);

    -- 11. Grant usage, create schema, create database role to DEPLOYMENT_ADMIN so it retains access after ownership transfer
    execute immediate 'grant usage on database identifier(:1) to role DEPLOYMENT_ADMIN' using (full_db_name);
    execute immediate 'grant create schema on database identifier(:1) to role DEPLOYMENT_ADMIN' using (full_db_name);
    execute immediate 'grant create database role on database identifier(:1) to role DEPLOYMENT_ADMIN' using (full_db_name);

    -- 12. Transfer database ownership to ENVIRONMENT SYSADMIN (last, so prior steps retain access)
    let env_sysadmin VARCHAR := :ENVIRONMENT_NAME || '_SYSADMIN';
    execute immediate 'grant ownership on database identifier(:1) to role identifier(:2) copy current grants' using (full_db_name, env_sysadmin);

    -- 13. Create DCM schema and project (ready to accept domain code)
    let dcm_schema VARCHAR := :full_db_name || '.DCM';
    execute immediate 'create schema if not exists identifier(:1) with managed access' using (dcm_schema);
    let dcm_project_name VARCHAR := :DOMAIN_NAME || '_' || :DB_NAME || '_PROJECT';
    let dcm_project_fqn VARCHAR := :full_db_name || '.DCM.' || :dcm_project_name;
    execute immediate 'create dcm project if not exists identifier(:1)' using (dcm_project_fqn);

    -- 14. Grant domain SYSADMIN access to DCM schema and project ownership (for CI/CD deployments)
    execute immediate 'grant role ' || :domain_sysadmin_role || ' to role DEPLOYMENT_ADMIN';
    execute immediate 'grant usage on schema ' || :dcm_schema || ' to role ' || :domain_sysadmin_role;
    execute immediate 'grant ownership on dcm project ' || :dcm_project_fqn || ' to role ' || :domain_sysadmin_role || ' copy current grants';

    return 'SUCCESS: Database "' || :full_db_name || '" deployed with DB_R, DB_RW, DB_RWC roles and DCM project.';
end;
$$
;
