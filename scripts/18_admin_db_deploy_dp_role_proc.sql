-- ============================================================================
-- RBAC FRAMEWORK: Step 18 - DEPLOY_DP_ROLE Procedure
-- ============================================================================
-- Purpose: Creates a bespoke data product (DP) account-level role that wraps
--          a read-only database role, enabling individual-level permissioning
--          outside of Okta functional roles.
--
--          The new account role is granted the specified database role (must be
--          a _R role) and ownership is transferred to the domain RBAC role.
--
-- Owner:   DEPLOYMENT_ADMIN (executes with owner's rights)
-- Params:  DP_NAME           - data product name (used in the role name)
--          DATABASE_NAME     - full database name (e.g. DEV_HR_CORE_DB)
--          DATABASE_ROLE_NAME- read database role to grant (e.g. EMPLOYEES_R)
--
-- Resulting role name: <DP_NAME>_DP
-- Allowed callers: DEPLOYMENT_ADMIN, ACCOUNTADMIN, <ENV>_RBAC, <ENV>_<DOMAIN>_RBAC
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure DEPLOY_DP_ROLE(
    DP_NAME VARCHAR,
    DATABASE_NAME VARCHAR,
    DATABASE_ROLE_NAME VARCHAR
)
returns VARCHAR
language sql
comment = 'Creates a data product account role granted a read-only database role, owned by domain RBAC.'
execute as owner
as
$$
begin
    -- -----------------------------------------------------------------------
    -- 0. Validate inputs
    -- -----------------------------------------------------------------------
    if (:DP_NAME IS NULL or trim(:DP_NAME) = '') then
        return 'ERROR: DP_NAME is required.';
    end if;
    if (:DATABASE_NAME IS NULL or trim(:DATABASE_NAME) = '') then
        return 'ERROR: DATABASE_NAME is required.';
    end if;
    if (:DATABASE_ROLE_NAME IS NULL or trim(:DATABASE_ROLE_NAME) = '') then
        return 'ERROR: DATABASE_ROLE_NAME is required.';
    end if;

    -- Check database exists
    let db_check INT := 0;
    SHOW DATABASES like :DATABASE_NAME;
    let db_rs RESULTSET := (select count(*) as CNT from table(result_scan(last_query_id())));
    let db_cur cursor for db_rs;
    open db_cur;
    FETCH db_cur into db_check;
    CLOSE db_cur;

    if (:db_check = 0) then
        return 'ERROR: Database "' || :DATABASE_NAME || '" does not exist.';
    end if;

    -- -----------------------------------------------------------------------
    -- 1. Infer ENVIRONMENT and DOMAIN from database TAGS
    -- -----------------------------------------------------------------------
    let env_name VARCHAR;
    let DOMAIN_NAME VARCHAR;

    select TAG_VALUE into :env_name
        from table(INFORMATION_SCHEMA.TAG_REFERENCES(:DATABASE_NAME, 'database'))
        where TAG_SCHEMA = 'TAGS' and TAG_NAME = 'ENVIRONMENT';

    select TAG_VALUE into :DOMAIN_NAME
        from table(INFORMATION_SCHEMA.TAG_REFERENCES(:DATABASE_NAME, 'database'))
        where TAG_SCHEMA = 'TAGS' and TAG_NAME = 'DOMAIN';

    if (:env_name IS NULL or :DOMAIN_NAME IS NULL) then
        return 'ERROR: Could not infer ENVIRONMENT or DOMAIN TAGS from database "' || :DATABASE_NAME || '".';
    end if;

    -- -----------------------------------------------------------------------
    -- 2. Validate caller has an RBAC-level role available
    -- -----------------------------------------------------------------------
    let env_rbac    VARCHAR := :env_name || '_RBAC';
    let domain_rbac VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_RBAC';

    if (not array_contains('DEPLOYMENT_ADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('ACCOUNTADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains(:env_rbac::VARIANT, parse_json(current_available_roles()))
        and not array_contains(:domain_rbac::VARIANT, parse_json(current_available_roles()))) then
        return 'ERROR: Caller must have DEPLOYMENT_ADMIN, ACCOUNTADMIN, ' || :env_rbac || ', or ' || :domain_rbac || ' available.';
    end if;

    -- -----------------------------------------------------------------------
    -- 3. Validate the database role is a read role (_R suffix)
    -- -----------------------------------------------------------------------
    if (not :DATABASE_ROLE_NAME ILIKE '%_R') then
        return 'ERROR: Only read roles (suffix _R) may be granted to data product roles. Received: "' || :DATABASE_ROLE_NAME || '".';
    end if;

    -- -----------------------------------------------------------------------
    -- 4. Construct and create the data product account role
    -- -----------------------------------------------------------------------
    let dp_role VARCHAR := :DP_NAME || '_DP';

    execute immediate 'create role if not exists identifier(:1)' using (dp_role);

    -- -----------------------------------------------------------------------
    -- 5. Grant the read database role to the new account role
    -- -----------------------------------------------------------------------
    let full_db_role VARCHAR := :DATABASE_NAME || '.' || :DATABASE_ROLE_NAME;
    execute immediate 'grant database role identifier(:1) to role identifier(:2)' using (full_db_role, dp_role);

    -- -----------------------------------------------------------------------
    -- 6. Transfer ownership to DOMAIN RBAC role
    -- -----------------------------------------------------------------------
    execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (dp_role, domain_rbac);

    return 'SUCCESS: Data product role "' || :dp_role || '" created and granted ' || :full_db_role || '.';
end;
$$
;
