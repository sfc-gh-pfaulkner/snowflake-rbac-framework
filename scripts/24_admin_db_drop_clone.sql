-- ============================================================================
-- RBAC FRAMEWORK: Step 24 - DROP_CLONE Procedure (unified WIP/TEST/UAT/PREPROD)
-- ============================================================================
-- Purpose: Drops an ephemeral clone database (WIP, TEST, UAT, or PREPROD) and revokes the
--          developer role's clone-specific grants.
--
--          SAFETY: Refuses to drop any database whose name starts with PROD.
--
--          If no other clones exist for the same domain, also revokes the
--          source-read and warehouse grants (since no clone needs them).
--
-- Caller:  Must be called as the domain SYSADMIN (e.g. DEV_HR_SYSADMIN)
-- Params:  ISSUE_ID         - GitHub Issue identifier (e.g. '1', '42')
--          ENVIRONMENT_NAME - source environment (e.g. 'DEV')
--          DOMAIN_NAME      - registered domain (e.g. 'HR')
--          DB_NAME          - logical database name (e.g. 'CORE')
--          CLONE_TYPE       - 'WIP', 'TEST', 'UAT', or 'PREPROD'
--
-- Derived clone name: <CLONE_TYPE>_<ISSUE_ID>_<DOMAIN>_<DB_NAME>_DB
--
-- Architecture:
--   _DROP_CLONE (EXECUTE AS OWNER / DEPLOYMENT_ADMIN)
--     - Revokes grants and drops the clone (requires MANAGE GRANTS)
--   DROP_CLONE (EXECUTE AS CALLER / domain SYSADMIN)
--     - Validates caller, delegates to helper
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

-- --------------------------------------------------------------------------
-- Helper: _DROP_CLONE (elevated privileges via DEPLOYMENT_ADMIN)
-- --------------------------------------------------------------------------
create or replace procedure ADMIN_DB.DEPLOY._DROP_CLONE(
    ISSUE_ID VARCHAR,
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    DB_NAME VARCHAR,
    CLONE_TYPE VARCHAR
)
returns VARCHAR
language sql
comment = 'Internal helper: drops a clone database and revokes clone-specific grants.'
execute as owner
as
$$
begin
    -- 0. Validate inputs
    if (:ISSUE_ID IS NULL or trim(:ISSUE_ID) = '') then
        return 'ERROR: ISSUE_ID is required.';
    end if;
    if (:ENVIRONMENT_NAME IS NULL or trim(:ENVIRONMENT_NAME) = '') then
        return 'ERROR: ENVIRONMENT_NAME is required.';
    end if;
    if (:DOMAIN_NAME IS NULL or trim(:DOMAIN_NAME) = '') then
        return 'ERROR: DOMAIN_NAME is required.';
    end if;
    if (:DB_NAME IS NULL or trim(:DB_NAME) = '') then
        return 'ERROR: DB_NAME is required.';
    end if;
    if (upper(:CLONE_TYPE) not in ('WIP', 'TEST', 'UAT', 'PREPROD', 'SAFE')) then
        return 'ERROR: CLONE_TYPE must be WIP, TEST, UAT, PREPROD, or SAFE.';
    end if;

    -- 1. Construct names
    let clone_type_upper VARCHAR := upper(:CLONE_TYPE);
    let clone_db   VARCHAR := :clone_type_upper || '_' || :ISSUE_ID || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';
    let dev_role   VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_DEVELOPER';
    let source_db  VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';
    let dev_wh     VARCHAR := :DOMAIN_NAME || '_DEV_WH';

    -- 2. SAFETY CHECK: refuse to drop anything starting with PROD
    if (:clone_db ILIKE 'PROD%') then
        return 'ERROR: Refusing to drop database "' || :clone_db || '". Databases starting with PROD are protected.';
    end if;

    -- 3. Check clone exists
    let db_exists INT := 0;
    SHOW DATABASES like :clone_db;
    let rs RESULTSET := (select count(*) as CNT from table(result_scan(last_query_id())));
    let cur cursor for rs;
    open cur;
    FETCH cur into db_exists;
    CLOSE cur;

    if (:db_exists = 0) then
        return 'SKIPPED: Database "' || :clone_db || '" does not exist.';
    end if;

    -- 4. Revoke clone-specific grants from DEVELOPER role
    begin
        execute immediate 'REVOKE usage on database identifier(:1) from role identifier(:2)' using (clone_db, dev_role);
    exception when OTHER then NULL;
    end;
    begin
        -- Revoke whichever database role was granted (RWC for WIP, R for others)
        if (:clone_type_upper = 'WIP') then
            let DB_RWC VARCHAR := :clone_db || '.DB_RWC';
            execute immediate 'REVOKE database role identifier(:1) from role identifier(:2)' using (DB_RWC, dev_role);
        else
            let DB_R VARCHAR := :clone_db || '.DB_R';
            -- Revoke from all possible roles that may have been granted
            let role_analyst    VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_ANALYST';
            let role_manager    VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_MANAGER';
            let role_datasteward VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_DATASTEWARD';
            let role_powerbi    VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_POWERBI';
            begin
                execute immediate 'REVOKE database role identifier(:1) from role identifier(:2)' using (DB_R, role_analyst);
            exception when OTHER then NULL;
            end;
            begin
                execute immediate 'REVOKE database role identifier(:1) from role identifier(:2)' using (DB_R, role_manager);
            exception when OTHER then NULL;
            end;
            begin
                execute immediate 'REVOKE database role identifier(:1) from role identifier(:2)' using (DB_R, role_datasteward);
            exception when OTHER then NULL;
            end;
            begin
                execute immediate 'REVOKE database role identifier(:1) from role identifier(:2)' using (DB_R, role_powerbi);
            exception when OTHER then NULL;
            end;
        end if;
    exception when OTHER then NULL;
    end;

    -- 5. Revoke source/warehouse grants only if no other clones exist for this DOMAIN
    let other_clones INT := 0;
    let clone_pattern VARCHAR := '%_' || :DOMAIN_NAME || '_' || :DB_NAME || '_DB';
    SHOW DATABASES like :clone_pattern;
    let clone_rs RESULTSET := (
        select count(*) as CNT from table(result_scan(last_query_id()))
        where "name" != :clone_db
          and "name" != :source_db
    );
    let clone_cur cursor for clone_rs;
    open clone_cur;
    FETCH clone_cur into other_clones;
    CLOSE clone_cur;

    if (:other_clones = 0) then
        begin
            execute immediate 'REVOKE usage on database identifier(:1) from role identifier(:2)' using (source_db, dev_role);
        exception when OTHER then NULL;
        end;
        begin
            let source_db_r VARCHAR := :source_db || '.DB_R';
            execute immediate 'REVOKE database role identifier(:1) from role identifier(:2)' using (source_db_r, dev_role);
        exception when OTHER then NULL;
        end;
        begin
            execute immediate 'REVOKE usage on warehouse identifier(:1) from role identifier(:2)' using (dev_wh, dev_role);
        exception when OTHER then NULL;
        end;
        begin
            execute immediate 'REVOKE operate on warehouse identifier(:1) from role identifier(:2)' using (dev_wh, dev_role);
        exception when OTHER then NULL;
        end;
    end if;

    -- 6. Take ownership and drop the clone database
    execute immediate 'grant ownership on database identifier(:1) to role DEPLOYMENT_ADMIN copy current grants' using (clone_db);
    execute immediate 'drop database identifier(:1)' using (clone_db);

    return 'SUCCESS: ' || :clone_type_upper || ' clone "' || :clone_db || '" dropped. Developer grants revoked.';
end;
$$
;

-- --------------------------------------------------------------------------
-- Main: DROP_CLONE (runs as domain SYSADMIN caller)
-- --------------------------------------------------------------------------
create or replace procedure ADMIN_DB.DEPLOY.DROP_CLONE(
    ISSUE_ID VARCHAR,
    ENVIRONMENT_NAME VARCHAR,
    DOMAIN_NAME VARCHAR,
    DB_NAME VARCHAR,
    CLONE_TYPE VARCHAR
)
returns VARCHAR
language sql
comment = 'Drops a clone database and revokes grants. Must be called as the domain SYSADMIN or DEPLOYMENT_ADMIN.'
execute as caller
as
$$
begin
    if (upper(:CLONE_TYPE) not in ('WIP', 'TEST', 'UAT', 'PREPROD', 'SAFE')) then
        return 'ERROR: CLONE_TYPE must be WIP, TEST, UAT, PREPROD, or SAFE.';
    end if;

    -- Validate caller is the DOMAIN SYSADMIN, DEVELOPER, or DEPLOYMENT_ADMIN
    let domain_sysadmin VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_SYSADMIN';
    let domain_developer VARCHAR := :ENVIRONMENT_NAME || '_' || :DOMAIN_NAME || '_DEVELOPER';

    if (current_role() != :domain_sysadmin and current_role() != :domain_developer and current_role() != 'DEPLOYMENT_ADMIN') then
        return 'ERROR: Must be called as ' || :domain_sysadmin || ', ' || :domain_developer || ', or DEPLOYMENT_ADMIN. Current role: ' || current_role();
    end if;

    -- Delegate to the OWNER proc
    let result VARCHAR;
    CALL ADMIN_DB.DEPLOY._DROP_CLONE(:ISSUE_ID, :ENVIRONMENT_NAME, :DOMAIN_NAME, :DB_NAME, :CLONE_TYPE) into :result;
    return :result;
end;
$$
;

-- --------------------------------------------------------------------------
-- Grant USAGE on drop clone procedures to all domain SYSADMIN and DEVELOPER roles
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
        grant_sql := 'grant usage on procedure ADMIN_DB.DEPLOY.DROP_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || rec.ROLE_NAME;
        execute immediate :grant_sql;
        grant_sql := 'grant usage on procedure ADMIN_DB.DEPLOY._DROP_CLONE(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR) to role ' || rec.ROLE_NAME;
        execute immediate :grant_sql;
    end for;
    return 'Grants applied';
end;
$$;
