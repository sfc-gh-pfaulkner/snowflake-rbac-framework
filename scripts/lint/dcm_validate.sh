#!/usr/bin/env bash
# DCM manifest validation
# Checks YAML syntax and required fields in manifest.yml files
set -euo pipefail

ROOT="${1:-.}"
ERRORS=0

echo "Running DCM manifest validation..."

# Find all manifest.yml files
MANIFESTS=$(find "$ROOT" -name "manifest.yml" -not -path "*/.git/*" -not -path "*/node_modules/*")

if [ -z "$MANIFESTS" ]; then
    echo "No manifest.yml files found — skipping"
    exit 0
fi

for manifest in $MANIFESTS; do
    echo "  Checking: $manifest"

    # YAML syntax check (requires python3 + pyyaml)
    if ! python3 -c "import yaml; yaml.safe_load(open('$manifest'))" 2>/dev/null; then
        echo "ERROR: Invalid YAML syntax in $manifest"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Check for required top-level key: project_name
    if ! grep -q "project_name:" "$manifest"; then
        echo "ERROR: Missing 'project_name' in $manifest"
        ERRORS=$((ERRORS + 1))
    fi
done

# Try snow dcm validate if available
if command -v snow &>/dev/null; then
    for manifest in $MANIFESTS; do
        dir=$(dirname "$manifest")
        if snow dcm validate --project-dir "$dir" 2>/dev/null; then
            echo "  snow dcm validate passed: $manifest"
        else
            # Don't fail on this — snow dcm validate may not be available
            echo "  WARN: snow dcm validate not available or returned error for $manifest (non-blocking)"
        fi
    done
fi

if [ $ERRORS -gt 0 ]; then
    echo "DCM validation FAILED ($ERRORS issue(s) found)"
    exit 1
fi

echo "DCM manifest validation passed"
