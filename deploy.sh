#!/usr/bin/env bash
# ============================================================================
# RBAC Framework Deployment Script
# Executes all framework scripts in order using Snowflake CLI.
# Usage: ./deploy.sh --connection <CONNECTION_NAME>
# ============================================================================

set -euo pipefail

CONNECTION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --connection|-c)
            CONNECTION="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 --connection <CONNECTION_NAME>"
            exit 1
            ;;
    esac
done

if [[ -z "$CONNECTION" ]]; then
    echo "ERROR: --connection is required."
    echo "Usage: $0 --connection <CONNECTION_NAME>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_PATH="$SCRIPT_DIR/scripts"

SCRIPTS=(
    "02_admin_db.sql"
    "03_admin_db_deploy_schema.sql"
    "04_admin_db_tags_schema.sql"
    "05_admin_db_database_roles.sql"
    "06_admin_db_deploy_schema_roles.sql"
    "07_admin_db_tags_schema_roles.sql"
    "08_admin_wh.sql"
    "09_admin_db_environments_table.sql"
    "10_admin_db_domains_table.sql"
    "11_admin_db_environment_tag.sql"
    "12_admin_db_domain_tag.sql"
    "13_admin_db_deploy_environment_proc.sql"
    "14_admin_db_deploy_domain_proc.sql"
    "15_admin_db_deploy_database_proc.sql"
    "16_admin_db_deploy_schema_proc.sql"
    "17_admin_db_deploy_warehouse_proc.sql"
    "18_admin_db_deploy_dp_role_proc.sql"
    "19_admin_db_deploy_clone.sql"
    "24_admin_db_drop_clone.sql"
    "26_admin_db_find_clone_blockers.sql"
    "30_pii_governance.sql"
)

echo "============================================"
echo "RBAC Framework Deployment"
echo "Connection: $CONNECTION"
echo "============================================"
echo ""

for script in "${SCRIPTS[@]}"; do
    echo "Running: $script"
    snow sql -f "$SCRIPTS_PATH/$script" -c "$CONNECTION"
    echo "  Done."
    echo ""
done

echo "============================================"
echo "Framework deployment complete."
echo ""
echo "Next steps:"
echo "  1. Write your deployment script (call DEPLOY_ENVIRONMENT, DEPLOY_DOMAIN, etc.)"
echo "  2. Deploy functional roles: cd functional_roles && snow dcm deploy -c $CONNECTION"
echo ""
echo "NOTE: Scripts 00_session_policy.sql and 01_deployment_admin.sql must be run"
echo "      separately by an ACCOUNTADMIN before running this script."
echo "============================================"
