-- ============================================================================
-- RBAC FRAMEWORK: Step 17 - DEPLOY_WAREHOUSE Procedure
-- ============================================================================
-- Purpose: Creates a warehouse within the RBAC framework, owned by the
--          environment SYSADMIN with USAGE granted to the domain READER role.
--
--          Domain admins may deploy Gen1 or Gen2 warehouses up to SMALL.
--          Higher-level admins may deploy any type/size including Snowpark-
--          optimized.
--
-- Owner:   DEPLOYMENT_ADMIN (executes with owner's rights)
-- Params:  ENVIRONMENT_NAME - registered environment (e.g. PRD, DEV)
--          DOMAIN_NAME      - registered domain (e.g. FINANCE, IT)
--          WH_NAME          - logical warehouse name
--          WH_TYPE          - GEN1, GEN2, or SNOWPARK_OPTIMIZED
--          WH_SIZE          - XSMALL, SMALL, MEDIUM, LARGE, XLARGE, etc.
--
-- Resulting WH name: <DOMAIN>_<WH_NAME>_WH
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure _CREATE_WAREHOUSE(
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    WH_NAME VARCHAR,
    WH_TYPE VARCHAR,
    WH_SIZE VARCHAR
)
returns VARCHAR
language sql
comment = 'Internal: creates a warehouse, assigns ownership to env SYSADMIN, grants USAGE to domain READER.'
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
    if (:DOMAIN_NAME IS NULL or trim(:DOMAIN_NAME) = '') then
        return 'ERROR: DOMAIN_NAME is required.';
    end if;
    if (:WH_NAME IS NULL or trim(:WH_NAME) = '') then
        return 'ERROR: WH_NAME is required.';
    end if;
    if (:WH_TYPE IS NULL or trim(:WH_TYPE) = '') then
        return 'ERROR: WH_TYPE is required.';
    end if;
    if (:WH_SIZE IS NULL or trim(:WH_SIZE) = '') then
        return 'ERROR: WH_SIZE is required.';
    end if;

    -- -----------------------------------------------------------------------
    -- 1. Determine caller privilege level
    -- -----------------------------------------------------------------------
    let env_sysadmin    VARCHAR := :ENVIRONMENT_NAME || '_SYSADMIN';
    let domain_sysadmin VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_SYSADMIN';

    let is_higher_admin BOOLEAN := (
        array_contains('DEPLOYMENT_ADMIN'::VARIANT, parse_json(current_available_roles()))
        or array_contains('SYSADMIN'::VARIANT, parse_json(current_available_roles()))
        or array_contains('ACCOUNTADMIN'::VARIANT, parse_json(current_available_roles()))
        or array_contains(:env_sysadmin::VARIANT, parse_json(current_available_roles()))
    );

    let is_domain_admin BOOLEAN :=
        array_contains(:domain_sysadmin::VARIANT, parse_json(current_available_roles()));

    if (not :is_higher_admin and not :is_domain_admin) then
        return 'ERROR: Caller must have DEPLOYMENT_ADMIN, SYSADMIN, ACCOUNTADMIN, ' || :env_sysadmin || ', or ' || :domain_sysadmin || ' available.';
    end if;

    -- -----------------------------------------------------------------------
    -- 2. Validate type
    -- -----------------------------------------------------------------------
    let wh_type_upper VARCHAR := upper(:WH_TYPE);
    if (:wh_type_upper not in ('GEN1', 'GEN2', 'SNOWPARK_OPTIMIZED')) then
        return 'ERROR: WH_TYPE must be GEN1, GEN2, or SNOWPARK_OPTIMIZED.';
    end if;

    -- -----------------------------------------------------------------------
    -- 3. Validate size
    -- -----------------------------------------------------------------------
    let wh_size_upper VARCHAR := upper(:WH_SIZE);
    let allowed_sizes ARRAY := array_construct('XSMALL','SMALL','MEDIUM','LARGE','XLARGE','2XLARGE','3XLARGE','4XLARGE','5XLARGE','6XLARGE');
    if (not array_contains(:wh_size_upper::VARIANT, :allowed_sizes)) then
        return 'ERROR: WH_SIZE must be one of XSMALL, SMALL, MEDIUM, LARGE, XLARGE, 2XLARGE, 3XLARGE, 4XLARGE, 5XLARGE, 6XLARGE.';
    end if;

    -- -----------------------------------------------------------------------
    -- 4. Enforce DOMAIN admin restrictions (Gen1/Gen2, up to SMALL only)
    -- -----------------------------------------------------------------------
    if (:is_domain_admin and not :is_higher_admin) then
        if (:wh_type_upper = 'SNOWPARK_OPTIMIZED') then
            return 'ERROR: Domain admins cannot DEPLOY SNOWPARK_OPTIMIZED warehouses. Contact a higher-level admin.';
        end if;

        let domain_allowed_sizes ARRAY := array_construct('XSMALL', 'SMALL');
        if (not array_contains(:wh_size_upper::VARIANT, :domain_allowed_sizes)) then
            return 'ERROR: Domain admins can only DEPLOY warehouses up to SMALL. Contact a higher-level admin for larger sizes.';
        end if;
    end if;

    -- -----------------------------------------------------------------------
    -- 5. Construct full warehouse name
    -- -----------------------------------------------------------------------
    let full_wh_name VARCHAR := :DOMAIN_NAME || '_' || :WH_NAME || '_WH';

    -- -----------------------------------------------------------------------
    -- 6. Create warehouse (idempotent)
    --    If the warehouse already exists but is owned by another role,
    --    take ownership first (DEPLOYMENT_ADMIN has MANAGE grants).
    -- -----------------------------------------------------------------------
    begin
        execute immediate 'grant ownership on warehouse identifier(:1) to role DEPLOYMENT_ADMIN copy current grants' using (full_wh_name);
    exception
        when OTHER then
            NULL; -- Warehouse does not exist yet
    end;

    let create_sql VARCHAR := 'create warehouse if not exists identifier(:1) WAREHOUSE_SIZE = ''' || :wh_size_upper || ''' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE';

    if (:wh_type_upper = 'SNOWPARK_OPTIMIZED') then
        create_sql := :create_sql || ' WAREHOUSE_TYPE = ''SNOWPARK-OPTIMIZED''';
    end if;

    execute immediate :create_sql using (full_wh_name);

    -- -----------------------------------------------------------------------
    -- 8. Tag with ENVIRONMENT and DOMAIN
    -- -----------------------------------------------------------------------
    execute immediate 'alter warehouse identifier(:1) set tag ADMIN_DB.TAGS.ENVIRONMENT = :2' using (full_wh_name, ENVIRONMENT_NAME);
    execute immediate 'alter warehouse identifier(:1) set tag ADMIN_DB.TAGS.DOMAIN = :2' using (full_wh_name, DOMAIN_NAME);

    -- -----------------------------------------------------------------------
    -- 9. Transfer ownership to ENVIRONMENT SYSADMIN
    -- -----------------------------------------------------------------------
    execute immediate 'grant ownership on warehouse identifier(:1) to role identifier(:2) copy current grants' using (full_wh_name, env_sysadmin);

    -- -----------------------------------------------------------------------
    -- 10. Grant usage to DOMAIN READER role
    -- -----------------------------------------------------------------------
    let domain_reader VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_READER';
    execute immediate 'grant usage on warehouse identifier(:1) to role identifier(:2)' using (full_wh_name, domain_reader);

    -- -----------------------------------------------------------------------
    -- 11. Grant usage with grant option to DOMAIN SYSADMIN
    --     Allows DOMAIN admins to grant warehouse access to other roles
    --     (e.g. DEVELOPER roles for DEV clone DT refresh).
    -- -----------------------------------------------------------------------
    execute immediate 'grant usage on warehouse identifier(:1) to role identifier(:2) with grant option' using (full_wh_name, domain_sysadmin);

    return 'SUCCESS: Warehouse "' || :full_wh_name || '" (' || :wh_type_upper || ', ' || :wh_size_upper || ') deployed.';
end;
$$
;

-- --------------------------------------------------------------------------
-- Wrapper: DEPLOY_WAREHOUSE (EXECUTE AS CALLER)
-- Calls the internal helper then restores the session warehouse.
-- CREATE WAREHOUSE makes the new warehouse current; ownership transfer then
-- drops access.  USE WAREHOUSE is only allowed in caller-rights procedures.
-- --------------------------------------------------------------------------
create or replace procedure DEPLOY_WAREHOUSE(
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    WH_NAME VARCHAR,
    WH_TYPE VARCHAR,
    WH_SIZE VARCHAR
)
returns VARCHAR
language sql
comment = 'Creates a warehouse within the RBAC framework. Restores session warehouse after creation.'
execute as caller
as
$$
begin
    let result VARCHAR;
    CALL ADMIN_DB.DEPLOY._CREATE_WAREHOUSE(:ENVIRONMENT_NAME, :DOMAIN_NAME, :WH_NAME, :WH_TYPE, :WH_SIZE) into :result;
    use warehouse ADMIN_WH;
    return :result;
end;
$$
;
