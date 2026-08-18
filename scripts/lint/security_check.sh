#!/usr/bin/env bash
# Security linting for SQL files
# Flags: hardcoded passwords, overly permissive grants, direct ACCOUNTADMIN usage
set -euo pipefail

ERRORS=0
ROOT="${1:-.}"

# Files exempt from ACCOUNTADMIN checks (bootstrap scripts that require it)
EXEMPT_ACCOUNTADMIN="scripts/00_session_policy.sql|scripts/01_deployment_admin.sql|scripts/30_teardown.sql|scripts/lint/"

echo "Running security checks..."

# 1. Hardcoded passwords (PASSWORD = '...' or PASSWORD='...')
if grep -rniP "password\s*=\s*'" "$ROOT/scripts" "$ROOT/functional_roles" 2>/dev/null | grep -v '\.sh:'; then
    echo "ERROR: Hardcoded password detected"
    ERRORS=$((ERRORS + 1))
fi

# 2. GRANT ... TO PUBLIC (dangerous in almost all cases)
if grep -rniP 'grant\s+.*\s+to\s+(role\s+)?public' "$ROOT/scripts" "$ROOT/functional_roles" 2>/dev/null; then
    echo "ERROR: GRANT ... TO PUBLIC detected — use explicit roles instead"
    ERRORS=$((ERRORS + 1))
fi

# 3. Direct USE ROLE ACCOUNTADMIN or GRANT ... TO ROLE ACCOUNTADMIN outside exempt files
#    (references in error messages and ARRAY_CONTAINS checks are fine)
if grep -rniP '(use\s+role\s+accountadmin|grant\s+.*\s+to\s+role\s+accountadmin)' "$ROOT/scripts" "$ROOT/functional_roles" 2>/dev/null \
    | grep -vE "$EXEMPT_ACCOUNTADMIN" \
    | grep -viE '^\s*--'; then
    echo "ERROR: Direct USE ROLE ACCOUNTADMIN or GRANT TO ACCOUNTADMIN outside bootstrap scripts"
    ERRORS=$((ERRORS + 1))
fi

# 4. GRANT ALL PRIVILEGES (overly broad)
if grep -rniP 'grant\s+all\s+(privileges\s+)?on' "$ROOT/scripts" "$ROOT/functional_roles" 2>/dev/null \
    | grep -viE '^\s*--'; then
    echo "ERROR: GRANT ALL PRIVILEGES detected — use specific grants"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -gt 0 ]; then
    echo "Security lint FAILED ($ERRORS issue(s) found)"
    exit 1
fi

echo "Security checks passed"
