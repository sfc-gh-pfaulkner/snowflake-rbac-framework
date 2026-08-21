#!/bin/bash
set -euo pipefail

# ============================================================
# PARTIAL RESET (both accounts)
# ============================================================
# Keeps: ADMIN_DB, GOVERNANCE_DB, DEPLOYMENT_ADMIN, ADMIN_WH,
#        session policy, masking policies, tags (structure)
#
# Removes: domain databases, clones, domain warehouses,
#          domain/environment roles, functional roles,
#          environment + domain tag values (so they can be recreated)
#
# Run from: ~/Documents/GitHub/snowflake-rbac-framework
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$HOME/Documents/GitHub/SNOWFLAKE-FCI-CODE"

echo "=== Partial Reset: removing domain objects from both accounts ==="
echo ""

for CONN in DEVACC PRODACC; do
  echo "--- ${CONN}: dropping clones, databases, warehouses, roles ---"

  snow sql -c "$CONN" --role ACCOUNTADMIN --warehouse COMPUTE_WH -q "
-- 1. Drop all clone databases (WIP_, TEST_, UAT_, PREPROD_, SAFE_)
execute immediate \$\$
declare
    DB_NAME VARCHAR;
    c1 cursor for
        select DATABASE_NAME
        from SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
        where DATABASE_NAME rlike '^(WIP|TEST|UAT|PREPROD|SAFE)_[0-9]+_.*_DB\$';
begin
    open c1;
    for rec in c1 do
        DB_NAME := rec.DATABASE_NAME;
        execute immediate 'drop database if exists identifier(''' || :DB_NAME || ''')';
    end for;
    return 'Clone databases dropped';
end;
\$\$;

-- 2. Drop all environment databases (DEV_*_DB, PROD_*_DB)
execute immediate \$\$
declare
    DB_NAME VARCHAR;
    c1 cursor for
        select DATABASE_NAME
        from SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
        where DATABASE_NAME rlike '^(DEV|PROD)_[A-Z]+_[A-Z]+_DB\$';
begin
    open c1;
    for rec in c1 do
        DB_NAME := rec.DATABASE_NAME;
        execute immediate 'drop database if exists identifier(''' || :DB_NAME || ''')';
    end for;
    return 'Environment databases dropped';
end;
\$\$;

-- 3. Drop domain warehouses (keep ADMIN_WH and COMPUTE_WH)
execute immediate \$\$
declare
    WH_NAME VARCHAR;
    c1 cursor for
        select \"name\" as WH_NAME from table(result_scan(last_query_id()))
        where \"name\" rlike '^[A-Z]+_(INGEST|TRANSFORM|REPORTING|DEV)_WH\$';
begin
    show warehouses;
    open c1;
    for rec in c1 do
        WH_NAME := rec.WH_NAME;
        execute immediate 'drop warehouse if exists identifier(''' || :WH_NAME || ''')';
    end for;
    return 'Domain warehouses dropped';
end;
\$\$;

-- 4. Drop domain and environment roles (keep DEPLOYMENT_ADMIN)
execute immediate \$\$
declare
    role_name VARCHAR;
    c1 cursor for
        select \"name\" as ROLE_NAME from table(result_scan(last_query_id()))
        where
            \"name\" rlike '^(DEV|PROD)_(SYSADMIN|ETL|READER|RBAC)\$'
            or \"name\" rlike '^(DEV|PROD)_[A-Z]+_(SYSADMIN|ETL|READER|RBAC)\$'
            or \"name\" rlike '^(DEV|PROD)_[A-Z]+_(ANALYST|MANAGER|DATASTEWARD|POWERBI|DEVELOPER)\$'
            or \"name\" rlike '^[A-Z_]+_DP\$';
begin
    show roles in account;
    open c1;
    for rec in c1 do
        role_name := rec.ROLE_NAME;
        execute immediate 'drop role if exists identifier(''' || :role_name || ''')';
    end for;
    return 'Domain roles dropped';
end;
\$\$;

-- 5. Remove environment and domain tag values from ADMIN_DB.DEPLOY
execute immediate \$\$
begin
    delete from ADMIN_DB.DEPLOY.ENVIRONMENTS;
    delete from ADMIN_DB.DEPLOY.DOMAINS;
exception
    when other then null;
end;
\$\$;

-- 6. Drop the functional_roles DCM project (will be recreated by provisioning)
execute immediate \$\$
begin
    drop dcm project if exists ADMIN_DB.DEPLOY.FUNCTIONAL_ROLES_PROJECT;
exception
    when other then null;
end;
\$\$;
"

  echo "  ${CONN}: done"
  echo ""
done

echo "=== Partial reset complete. Now re-provision: ==="
echo ""
echo "  cd ${CODE_DIR}"
echo "  snow sql -f setup/provision_databases.sql -c DEVACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH"
echo "  snow sql -f setup/provision_databases.sql -c PRODACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH"
echo "  snow dcm deploy --from functional_roles --target DEV -c DEVACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH"
echo "  snow dcm deploy --from functional_roles --target PROD -c PRODACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH"
echo ""
