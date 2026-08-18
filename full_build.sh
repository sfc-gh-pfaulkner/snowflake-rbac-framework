# ============================================================
# FULL DEPLOY (both accounts)
# Run from: ~/Documents/GitHub
# ============================================================

# --- 2. Deploy RBAC framework (both accounts) ---
snow sql -f scripts/00_session_policy.sql -c DEVACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
snow sql -f scripts/01_deployment_admin.sql -c DEVACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
./deploy.sh --connection DEVACC

snow sql -f scripts/00_session_policy.sql -c PRODACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
snow sql -f scripts/01_deployment_admin.sql -c PRODACC --role ACCOUNTADMIN --warehouse COMPUTE_WH
./deploy.sh --connection PRODACC

# --- 3. Provision domains, databases, warehouses, roles (both accounts) ---
cd ~/Documents/GitHub/SNOWFLAKE-FCI-CODE
snow sql -f setup/provision_databases.sql -c DEVACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH
snow sql -f setup/provision_databases.sql -c PRODACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH

# --- 4. Deploy functional roles (both accounts) ---
snow dcm deploy --from functional_roles --target DEV -c DEVACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH
snow dcm deploy --from functional_roles --target PROD -c PRODACC --role DEPLOYMENT_ADMIN --warehouse ADMIN_WH

# --- 5. Grant DEVELOPER role to test user (no Okta) ---
snow sql -c DEVACC --role ACCOUNTADMIN --warehouse COMPUTE_WH -q "grant role DEV_HR_DEVELOPER to user FCRICK;"
