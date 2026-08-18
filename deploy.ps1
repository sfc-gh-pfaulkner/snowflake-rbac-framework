# ============================================================================
# RBAC Framework Deployment Script (PowerShell)
# Executes all framework scripts in order using Snowflake CLI.
# Usage: pwsh -File deploy.ps1 -Connection <CONNECTION_NAME>
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Connection
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$ScriptsPath = Join-Path $ScriptDir "scripts"

$Scripts = @(
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

Write-Host "============================================"
Write-Host "RBAC Framework Deployment"
Write-Host "Connection: $Connection"
Write-Host "============================================"
Write-Host ""

foreach ($script in $Scripts) {
    Write-Host "Running: $script"
    $filePath = Join-Path $ScriptsPath $script
    snow sql -f $filePath -c $Connection
    if ($LASTEXITCODE -ne 0) {
        Write-Error "FAILED: $script"
        exit 1
    }
    Write-Host "  Done."
    Write-Host ""
}

Write-Host "============================================"
Write-Host "Framework deployment complete."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Write your deployment script (call DEPLOY_ENVIRONMENT, DEPLOY_DOMAIN, etc.)"
Write-Host "  2. Deploy functional roles: cd functional_roles; snow dcm deploy -c $Connection"
Write-Host ""
Write-Host "NOTE: Scripts 00_session_policy.sql and 01_deployment_admin.sql must be run"
Write-Host "      separately by an ACCOUNTADMIN before running this script."
Write-Host "============================================"
