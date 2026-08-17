-- ============================================================================
-- RBAC FRAMEWORK: Step 13 - DEPLOY_ENVIRONMENT Procedure
-- ============================================================================
-- Purpose: Onboards a new environment into the RBAC framework by creating
--          top-level account roles, registering the environment, and updating
--          the ENVIRONMENT tag with the new allowed value.
--
-- Owner:   DEPLOYMENT_ADMIN (executes with owner's rights)
-- Params:  ENVIRONMENT_NAME  - short identifier (e.g. PRD, DEV)
--          DESCRIPTION       - human-readable description
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure DEPLOY_ENVIRONMENT(
    ENVIRONMENT_NAME VARCHAR,
    DESCRIPTION VARCHAR
)
returns VARCHAR
language sql
comment = 'Onboards a new environment: creates roles, registers in lookup table, updates tag.'
execute as owner
as
$$
begin
    -- -----------------------------------------------------------------------
    -- 0. Validate inputs
    -- -----------------------------------------------------------------------
    if (:ENVIRONMENT_NAME IS NULL or trim(:ENVIRONMENT_NAME) = '') then
        return 'ERROR: ENVIRONMENT_NAME is required.';
    end if;

    -- -----------------------------------------------------------------------
    -- 1. Validate caller has an appropriate role available
    -- -----------------------------------------------------------------------
    if (not array_contains('DEPLOYMENT_ADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('SYSADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('ACCOUNTADMIN'::VARIANT, parse_json(current_available_roles()))) then
        return 'ERROR: Caller must have DEPLOYMENT_ADMIN, SYSADMIN, or ACCOUNTADMIN available.';
    end if;

    -- -----------------------------------------------------------------------
    -- 2. Check ENVIRONMENT does not already exist
    -- -----------------------------------------------------------------------
    let env_count INT;
    select count(*) into :env_count
        from ADMIN_DB.DEPLOY.ENVIRONMENTS
        where ENVIRONMENT = :ENVIRONMENT_NAME;

    if (:env_count > 0) then
        return 'ERROR: Environment "' || :ENVIRONMENT_NAME || '" already exists.';
    end if;

    -- -----------------------------------------------------------------------
    -- 3. Create ENVIRONMENT-level account roles
    -- -----------------------------------------------------------------------
    let role_sysadmin VARCHAR := :ENVIRONMENT_NAME || '_SYSADMIN';
    let role_etl      VARCHAR := :ENVIRONMENT_NAME || '_ETL';
    let role_reader   VARCHAR := :ENVIRONMENT_NAME || '_READER';
    let role_rbac     VARCHAR := :ENVIRONMENT_NAME || '_RBAC';

    execute immediate 'create role if not exists identifier(:1)' using (role_sysadmin);
    execute immediate 'create role if not exists identifier(:1)' using (role_etl);
    execute immediate 'create role if not exists identifier(:1)' using (role_reader);
    execute immediate 'create role if not exists identifier(:1)' using (role_rbac);

    -- -----------------------------------------------------------------------
    -- 4. Grant ownership to USERADMIN
    -- -----------------------------------------------------------------------
    execute immediate 'grant ownership on role identifier(:1) to role USERADMIN REVOKE current grants' using (role_sysadmin);
    execute immediate 'grant ownership on role identifier(:1) to role USERADMIN REVOKE current grants' using (role_etl);
    execute immediate 'grant ownership on role identifier(:1) to role USERADMIN REVOKE current grants' using (role_reader);
    execute immediate 'grant ownership on role identifier(:1) to role USERADMIN REVOKE current grants' using (role_rbac);

    -- -----------------------------------------------------------------------
    -- 5. Grant RBAC role to USERADMIN; others to SYSADMIN
    -- -----------------------------------------------------------------------
    execute immediate 'grant role identifier(:1) to role USERADMIN' using (role_rbac);
    execute immediate 'grant role identifier(:1) to role SYSADMIN' using (role_sysadmin);
    execute immediate 'grant role identifier(:1) to role SYSADMIN' using (role_etl);
    execute immediate 'grant role identifier(:1) to role SYSADMIN' using (role_reader);

    -- -----------------------------------------------------------------------
    -- 6. Role hierarchy: READER → ETL → SYSADMIN
    -- -----------------------------------------------------------------------
    execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_reader, role_etl);
    execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_etl, role_sysadmin);

    -- -----------------------------------------------------------------------
    -- 7. Register ENVIRONMENT in lookup table
    -- -----------------------------------------------------------------------
    insert into ADMIN_DB.DEPLOY.ENVIRONMENTS (ENVIRONMENT, DESCRIPTION)
        values (:ENVIRONMENT_NAME, :DESCRIPTION);

    -- -----------------------------------------------------------------------
    -- 8. Add ENVIRONMENT as allowed value on the ENVIRONMENT tag
    -- -----------------------------------------------------------------------
    let alter_tag_sql VARCHAR := 'alter tag ADMIN_DB.TAGS.ENVIRONMENT ADD ALLOWED_VALUES ''' || :ENVIRONMENT_NAME || '''';
    execute immediate :alter_tag_sql;

    return 'SUCCESS: Environment "' || :ENVIRONMENT_NAME || '" deployed.';
end;
$$
;
