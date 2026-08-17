-- ============================================================================
-- RBAC FRAMEWORK: Step 14 - DEPLOY_DOMAIN Procedure
-- ============================================================================
-- Purpose: Onboards a new domain into the RBAC framework. For each registered
--          environment, creates domain-level account roles, assigns ownership
--          to the environment RBAC role, grants them up to the environment
--          SYSADMIN, registers the domain, and updates the DOMAIN tag.
--
--          Safe to re-run when new environments are added — uses CREATE IF NOT
--          EXISTS and COPY CURRENT GRANTS for non-destructive replay.
--
-- Owner:   DEPLOYMENT_ADMIN (executes with owner's rights)
-- Params:  DOMAIN_NAME  - short identifier (e.g. FINANCE, IT, RESEARCH)
--          DESCRIPTION  - human-readable description
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure DEPLOY_DOMAIN(
    DOMAIN_NAME VARCHAR,
    DESCRIPTION VARCHAR
)
returns VARCHAR
language sql
comment = 'Onboards a domain: creates roles per environment, registers in lookup table, updates tag.'
execute as owner
as
$$
begin
    -- -----------------------------------------------------------------------
    -- 0. Validate inputs
    -- -----------------------------------------------------------------------
    if (:DOMAIN_NAME IS NULL or trim(:DOMAIN_NAME) = '') then
        return 'ERROR: DOMAIN_NAME is required.';
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
    -- 2. For each registered ENVIRONMENT, create DOMAIN roles
    -- -----------------------------------------------------------------------
    let env_cursor cursor for
        select ENVIRONMENT from ADMIN_DB.DEPLOY.ENVIRONMENTS;

    for env in env_cursor do
        let env_name VARCHAR := env.ENVIRONMENT;

        let role_sysadmin VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_SYSADMIN';
        let role_etl      VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_ETL';
        let role_reader   VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_READER';
        let role_rbac     VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_RBAC';

        -- Create roles (idempotent)
        execute immediate 'create role if not exists identifier(:1)' using (role_sysadmin);
        execute immediate 'create role if not exists identifier(:1)' using (role_etl);
        execute immediate 'create role if not exists identifier(:1)' using (role_reader);
        execute immediate 'create role if not exists identifier(:1)' using (role_rbac);

        -- Ownership to ENVIRONMENT RBAC role (non-destructive)
        let env_rbac VARCHAR := :env_name || '_RBAC';
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_sysadmin, env_rbac);
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_etl, env_rbac);
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_reader, env_rbac);
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_rbac, env_rbac);

        -- Grant all DOMAIN roles up to ENVIRONMENT SYSADMIN
        let env_sysadmin VARCHAR := :env_name || '_SYSADMIN';
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_sysadmin, env_sysadmin);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_etl, env_sysadmin);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_reader, env_sysadmin);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_rbac, env_sysadmin);

        -- Role hierarchy: READER → ETL → SYSADMIN
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_reader, role_etl);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_etl, role_sysadmin);

        -- Create functional roles (idempotent)
        let role_analyst     VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_ANALYST';
        let role_manager     VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_MANAGER';
        let role_datasteward VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_DATASTEWARD';
        let role_powerbi     VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_POWERBI';

        execute immediate 'create role if not exists identifier(:1)' using (role_analyst);
        execute immediate 'create role if not exists identifier(:1)' using (role_manager);
        execute immediate 'create role if not exists identifier(:1)' using (role_datasteward);
        execute immediate 'create role if not exists identifier(:1)' using (role_powerbi);

        -- Functional roles roll up to domain SYSADMIN
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_analyst, role_sysadmin);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_manager, role_sysadmin);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_datasteward, role_sysadmin);
        execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_powerbi, role_sysadmin);

        -- Ownership of functional roles to domain RBAC role
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_analyst, role_rbac);
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_manager, role_rbac);
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_datasteward, role_rbac);
        execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_powerbi, role_rbac);

        -- DEVELOPER role (DEV environments only)
        if (:env_name = 'DEV') then
            let role_developer VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_DEVELOPER';
            execute immediate 'create role if not exists identifier(:1)' using (role_developer);
            execute immediate 'grant role identifier(:1) to role identifier(:2)' using (role_developer, role_sysadmin);
            execute immediate 'grant ownership on role identifier(:1) to role identifier(:2) copy current grants' using (role_developer, role_rbac);

            -- Grant DEVELOPER access to ADMIN_DB and clone/drop procedures
            execute immediate 'grant usage on database ADMIN_DB to role identifier(:1)' using (role_developer);
            execute immediate 'grant usage on schema ADMIN_DB.DEPLOY to role identifier(:1)' using (role_developer);
            begin
                let g1 VARCHAR := 'grant usage on procedure ADMIN_DB.DEPLOY.DEPLOY_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || :role_developer;
                let g2 VARCHAR := 'grant usage on procedure ADMIN_DB.DEPLOY.DROP_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || :role_developer;
                execute immediate :g1;
                execute immediate :g2;
            exception
                when other then null; -- Clone procedures may not exist on first deployment
            end;
        end if;

        -- Grant DOMAIN SYSADMIN access to ADMIN_DB and clone procedures
        execute immediate 'grant usage on database ADMIN_DB to role identifier(:1)' using (role_sysadmin);
        execute immediate 'grant usage on schema ADMIN_DB.DEPLOY to role identifier(:1)' using (role_sysadmin);
        begin
            let grant_sql_1 VARCHAR := 'grant usage on procedure ADMIN_DB.DEPLOY.DEPLOY_DEV_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || :role_sysadmin;
            let grant_sql_2 VARCHAR := 'grant usage on procedure ADMIN_DB.DEPLOY._PROVISION_DEV_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || :role_sysadmin;
            execute immediate :grant_sql_1;
            execute immediate :grant_sql_2;
        exception
            when OTHER then
                NULL; -- Clone procedures may not exist on first deployment
        end;
    end for;

    -- -----------------------------------------------------------------------
    -- 3. Merge DOMAIN into lookup table
    -- -----------------------------------------------------------------------
    merge into ADMIN_DB.DEPLOY.DOMAINS as tgt
    using (select :DOMAIN_NAME as DOMAIN, :DESCRIPTION as DESCRIPTION) as src
        on tgt.DOMAIN = src.DOMAIN
    when matched then update set tgt.DESCRIPTION = src.DESCRIPTION
    when not matched then insert (DOMAIN, DESCRIPTION) values (src.DOMAIN, src.DESCRIPTION);

    -- -----------------------------------------------------------------------
    -- 4. Add DOMAIN as allowed value on the DOMAIN tag (idempotent check)
    -- -----------------------------------------------------------------------
    let tag_exists INT;
    select count(*) into :tag_exists
        from table(INFORMATION_SCHEMA.TAG_REFERENCES('ADMIN_DB.TAGS.DOMAIN', 'tag'))
        where 0 = 1;

    -- Snowflake ADD ALLOWED_VALUES is idempotent if value already exists
    let alter_tag_sql VARCHAR := 'alter tag ADMIN_DB.TAGS.DOMAIN ADD ALLOWED_VALUES ''' || :DOMAIN_NAME || '''';
    execute immediate :alter_tag_sql;

    -- -----------------------------------------------------------------------
    -- 5. Create Power BI service user per ENVIRONMENT (idempotent)
    -- -----------------------------------------------------------------------
    let env_cursor2 cursor for
        select ENVIRONMENT from ADMIN_DB.DEPLOY.ENVIRONMENTS;

    for env2 in env_cursor2 do
        let env_name2 VARCHAR := env2.ENVIRONMENT;
        let svc_user VARCHAR := 'SVC_POWERBI_' || :DOMAIN_NAME || '_' || :env_name2;
        let pbi_role VARCHAR := :env_name2 || '_' || :DOMAIN_NAME || '_POWERBI';
        let rpt_wh VARCHAR := :DOMAIN_NAME || '_REPORTING_WH';
        let create_user_sql VARCHAR := 'create user if not exists ' || :svc_user ||
            ' type = service' ||
            ' default_role = ' || :pbi_role ||
            ' default_warehouse = ' || :rpt_wh ||
            ' comment = ''Power BI service user for ' || :DOMAIN_NAME || ' DOMAIN''';
        execute immediate :create_user_sql;
    end for;

    return 'SUCCESS: Domain "' || :DOMAIN_NAME || '" deployed across all ENVIRONMENTS.';
end;
$$
;
