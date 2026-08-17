-- =============================================================================
-- RBAC FRAMEWORK: Full Tear-Down Script
-- =============================================================================
-- PURPOSE: Removes ALL objects created by the RBAC framework in a single account.
--          Run as ACCOUNTADMIN. Detects clones and main databases automatically.
--
-- WARNING: This is DESTRUCTIVE and IRREVERSIBLE. For end-to-end testing only.
-- =============================================================================

use role ACCOUNTADMIN;
use warehouse COMPUTE_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Remove session policy from account (must happen before dropping the DB)
-- ─────────────────────────────────────────────────────────────────────────────
alter account unset session policy;
drop session policy if exists GOVERNANCE_DB.POLICIES.BLOCK_PRIVILEGED_SECONDARY_ROLES;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Drop all clone databases (WIP_, TEST_, UAT_, PREPROD_, SAFE_)
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
declare
    DB_NAME VARCHAR;
    c1 cursor for
        select DATABASE_NAME
        from SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
        where DATABASE_NAME rlike '^(WIP|TEST|UAT|PREPROD|SAFE)_[0-9]+_.*_DB$';
begin
    open c1;
    for rec in c1 do
        DB_NAME := rec.DATABASE_NAME;
        execute immediate 'drop database if exists identifier(''' || :DB_NAME || ''')';
    end for;
    return 'Clone databases dropped';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Drop all environment databases (DEV_*_DB, PROD_*_DB)
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
declare
    DB_NAME VARCHAR;
    c1 cursor for
        select DATABASE_NAME
        from SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
        where DATABASE_NAME rlike '^(DEV|PROD)_[A-Z]+_[A-Z]+_DB$';
begin
    open c1;
    for rec in c1 do
        DB_NAME := rec.DATABASE_NAME;
        execute immediate 'drop database if exists identifier(''' || :DB_NAME || ''')';
    end for;
    return 'Environment databases dropped';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Detach masking policies from tags (breaks cross-DB dependency)
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
begin
    alter tag ADMIN_DB.TAGS.PII_CLASSIFICATION unset
        masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_STRING_PII_BY_DOMAIN,
        masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_NUMBER_PII_BY_DOMAIN,
        masking policy GOVERNANCE_DB.ACCESS_CONTROL.MP_DATE_PII_BY_DOMAIN;
exception
    when other then NULL;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Drop GOVERNANCE_DB and ADMIN_DB
-- ─────────────────────────────────────────────────────────────────────────────
drop database if exists GOVERNANCE_DB;
drop database if exists ADMIN_DB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Drop all framework warehouses (<DOMAIN>_*_WH and ADMIN_WH)
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
declare
    WH_NAME VARCHAR;
    c1 cursor for
        select "name" as WH_NAME from table(result_scan(last_query_id()))
        where "name" rlike '^[A-Z]+_(INGEST|TRANSFORM|REPORTING|DEV)_WH$'
           or "name" = 'ADMIN_WH';
begin
    show warehouses;
    open c1;
    for rec in c1 do
        WH_NAME := rec.WH_NAME;
        execute immediate 'drop warehouse if exists identifier(''' || :WH_NAME || ''')';
    end for;
    return 'Warehouses dropped';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Drop all framework account roles
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
declare
    role_name VARCHAR;
    c1 cursor for
        select "name" as ROLE_NAME from table(result_scan(last_query_id()))
        where
            -- Environment roles: DEV_SYSADMIN, DEV_ETL, DEV_READER, DEV_RBAC
            "name" rlike '^(DEV|PROD)_(SYSADMIN|ETL|READER|RBAC)$'
            -- Domain roles: DEV_HR_SYSADMIN, DEV_HR_ETL, etc.
            or "name" rlike '^(DEV|PROD)_[A-Z]+_(SYSADMIN|ETL|READER|RBAC)$'
            -- Functional roles: DEV_HR_ANALYST, DEV_HR_DEVELOPER, etc.
            or "name" rlike '^(DEV|PROD)_[A-Z]+_(ANALYST|MANAGER|DATASTEWARD|POWERBI|DEVELOPER)$'
            -- Data product roles
            or "name" rlike '^[A-Z_]+_DP$'
            -- Deployment admin
            or "name" = 'DEPLOYMENT_ADMIN';
begin
    show roles in account;
    open c1;
    for rec in c1 do
        role_name := rec.ROLE_NAME;
        execute immediate 'drop role if exists identifier(''' || :role_name || ''')';
    end for;
    return 'Roles dropped';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Drop service users (SVC_POWERBI_*)
-- ─────────────────────────────────────────────────────────────────────────────
execute immediate $$
declare
    user_name VARCHAR;
    c1 cursor for
        select "name" as USER_NAME from table(result_scan(last_query_id()))
        where "name" rlike '^SVC_POWERBI_';
begin
    show users in account;
    open c1;
    for rec in c1 do
        user_name := rec.USER_NAME;
        execute immediate 'drop user if exists identifier(''' || :user_name || ''')';
    end for;
    return 'Service users dropped';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Done
-- ─────────────────────────────────────────────────────────────────────────────
select 'TEARDOWN COMPLETE — all framework objects removed from this account.' as STATUS;
