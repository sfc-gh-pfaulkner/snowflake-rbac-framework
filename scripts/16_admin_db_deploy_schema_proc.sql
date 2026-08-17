-- ============================================================================
-- RBAC FRAMEWORK: Step 16 - DEPLOY_SCHEMA Procedure
-- ============================================================================
-- Purpose: Creates a managed-access schema within an existing RBAC-managed
--          database, creates schema-level database roles with future grants,
--          and wires them into the DB-level role hierarchy.
--
--          Fully replayable / non-destructive: uses CREATE IF NOT EXISTS,
--          COPY CURRENT GRANTS, and idempotent GRANT statements throughout.
--
-- Owner:   DEPLOYMENT_ADMIN (executes with owner's rights)
-- Params:  DATABASE_NAME - full database name (e.g. PRD_IT_CORE_DB)
--          SCHEMA_NAME   - schema to create (e.g. RAW, CURATED)
--
-- Infers:  ENVIRONMENT and DOMAIN from tags on the database.
-- ============================================================================

use role DEPLOYMENT_ADMIN;
use database ADMIN_DB;
use schema DEPLOY;
use warehouse ADMIN_WH;

create or replace procedure DEPLOY_SCHEMA(
    DATABASE_NAME VARCHAR,
    SCHEMA_NAME VARCHAR
)
returns VARCHAR
language sql
comment = 'Creates a managed-access schema with R/RW/RWC database roles and future grants.'
execute as owner
as
$$
begin
    -- -----------------------------------------------------------------------
    -- 0. Validate inputs
    -- -----------------------------------------------------------------------
    if (:DATABASE_NAME IS NULL or trim(:DATABASE_NAME) = '') then
        return 'ERROR: DATABASE_NAME is required.';
    end if;

    if (:SCHEMA_NAME IS NULL or trim(:SCHEMA_NAME) = '') then
        return 'ERROR: SCHEMA_NAME is required.';
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
    -- 2. Validate caller has an appropriate role available
    -- -----------------------------------------------------------------------
    let env_sysadmin_check VARCHAR := :env_name || '_SYSADMIN';
    let domain_sysadmin VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_SYSADMIN';

    if (not array_contains('DEPLOYMENT_ADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('SYSADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains('ACCOUNTADMIN'::VARIANT, parse_json(current_available_roles()))
        and not array_contains(:env_sysadmin_check::VARIANT, parse_json(current_available_roles()))
        and not array_contains(:domain_sysadmin::VARIANT, parse_json(current_available_roles()))) then
        return 'ERROR: Caller must have DEPLOYMENT_ADMIN, SYSADMIN, ACCOUNTADMIN, ' || :env_sysadmin_check || ', or ' || :domain_sysadmin || ' available.';
    end if;

    -- -----------------------------------------------------------------------
    -- 3. Create schema (managed access, idempotent)
    -- -----------------------------------------------------------------------
    let full_schema VARCHAR := :DATABASE_NAME || '.' || :SCHEMA_NAME;
    begin
        execute immediate 'create schema if not exists identifier(:1) with MANAGED ACCESS' using (full_schema);
    exception
        when OTHER then
            NULL; -- Schema already exists and is owned by another role — continue
    end;

    -- -----------------------------------------------------------------------
    -- 4. Create schema-level database roles (idempotent)
    -- -----------------------------------------------------------------------
    let role_r   VARCHAR := :DATABASE_NAME || '.' || :SCHEMA_NAME || '_R';
    let role_rw  VARCHAR := :DATABASE_NAME || '.' || :SCHEMA_NAME || '_RW';
    let role_rwc VARCHAR := :DATABASE_NAME || '.' || :SCHEMA_NAME || '_RWC';

    execute immediate 'create database role if not exists identifier(:1)' using (role_r);
    execute immediate 'create database role if not exists identifier(:1)' using (role_rw);
    execute immediate 'create database role if not exists identifier(:1)' using (role_rwc);

    -- -----------------------------------------------------------------------
    -- 5. Static grants - usage on schema
    -- -----------------------------------------------------------------------
    execute immediate 'grant usage on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);

    -- -----------------------------------------------------------------------
    -- 6. Grants - READ (_R role: future + existing objects)
    -- -----------------------------------------------------------------------
    execute immediate 'grant select on future tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant select on future views in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant select on future dynamic tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant select on future MATERIALIZED views in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant READ on future STAGES in schema ' || :full_schema || ' to database role ' || :role_r;
    execute immediate 'grant select on all tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant select on all views in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant select on all dynamic tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant select on all MATERIALIZED views in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_r);
    execute immediate 'grant READ on all STAGES in schema ' || :full_schema || ' to database role ' || :role_r;

    -- -----------------------------------------------------------------------
    -- 7. Grants - WRITE (_RW role: future + existing objects)
    -- -----------------------------------------------------------------------
    execute immediate 'grant insert on future tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant update on future tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant delete on future tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant TRUNCATE on future tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant operate on future PIPES in schema ' || :full_schema || ' to database role ' || :role_rw;
    execute immediate 'grant READ, WRITE on future STAGES in schema ' || :full_schema || ' to database role ' || :role_rw;
    execute immediate 'grant insert on all tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant update on all tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant delete on all tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant TRUNCATE on all tables in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant READ, WRITE on all STAGES in schema ' || :full_schema || ' to database role ' || :role_rw;

    -- -----------------------------------------------------------------------
    -- 8. Grants - usage on procedures/functions (_RW role: future + existing)
    -- -----------------------------------------------------------------------
    execute immediate 'grant usage on future PROCEDURES in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant usage on future FUNCTIONS in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant usage on all PROCEDURES in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);
    execute immediate 'grant usage on all FUNCTIONS in schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rw);

    -- -----------------------------------------------------------------------
    -- 9. Grants - create (_RWC role: schema-level DDL privileges)
    -- -----------------------------------------------------------------------
    execute immediate 'grant create table on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create view on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create procedure on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create FUNCTION on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create STAGE on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create dynamic table on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create MATERIALIZED view on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);
    execute immediate 'grant create PIPE on schema identifier(:1) to database role identifier(:2)' using (full_schema, role_rwc);

    -- -----------------------------------------------------------------------
    -- 10. Role hierarchy - schema roles grant up to each other and DB roles
    -- -----------------------------------------------------------------------
    let DB_R   VARCHAR := :DATABASE_NAME || '.DB_R';
    let DB_RW  VARCHAR := :DATABASE_NAME || '.DB_RW';
    let DB_RWC VARCHAR := :DATABASE_NAME || '.DB_RWC';

    -- Internal hierarchy: RWC → RW → R
    execute immediate 'grant database role identifier(:1) to database role identifier(:2)' using (role_r, role_rw);
    execute immediate 'grant database role identifier(:1) to database role identifier(:2)' using (role_rw, role_rwc);

    -- Roll up to DB-level roles
    execute immediate 'grant database role identifier(:1) to database role identifier(:2)' using (role_r, DB_R);
    execute immediate 'grant database role identifier(:1) to database role identifier(:2)' using (role_rw, DB_RW);
    execute immediate 'grant database role identifier(:1) to database role identifier(:2)' using (role_rwc, DB_RWC);

    -- -----------------------------------------------------------------------
    -- 11. Transfer ownership of schema roles to DOMAIN RBAC role
    -- -----------------------------------------------------------------------
    let domain_rbac VARCHAR := :env_name || '_' || :DOMAIN_NAME || '_RBAC';
    execute immediate 'grant ownership on database role identifier(:1) to role identifier(:2) copy current grants' using (role_r, domain_rbac);
    execute immediate 'grant ownership on database role identifier(:1) to role identifier(:2) copy current grants' using (role_rw, domain_rbac);
    execute immediate 'grant ownership on database role identifier(:1) to role identifier(:2) copy current grants' using (role_rwc, domain_rbac);

    -- -----------------------------------------------------------------------
    -- 12. Transfer schema ownership to DOMAIN SYSADMIN
    -- -----------------------------------------------------------------------
    execute immediate 'grant ownership on schema identifier(:1) to role identifier(:2) copy current grants' using (full_schema, domain_sysadmin);

    return 'SUCCESS: Schema "' || :full_schema || '" deployed with ' || :SCHEMA_NAME || '_R, _RW, _RWC roles.';
end;
$$
;
