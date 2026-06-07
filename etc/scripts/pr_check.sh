#!/bin/bash
# pr-check.sh - Verify all shell scripts with bash -n and shellcheck

set -euo pipefail

SCRIPTS_DIR="${1:-.}"
FAILED=0

echo "=== Running PR checks on shell scripts ==="
echo

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "Error: shellcheck not found"
    exit 1
fi

# Find all .sh files
while IFS= read -r script; do
    echo "Checking: $script"

    # Syntax check with bash -n
    if ! bash -n "$script" 2>&1; then
        echo "  ❌ bash -n failed"
        FAILED=$((FAILED + 1))
    else
        echo "  ✓ bash -n passed"
    fi

    if ! shellcheck "$script" 2>&1; then
        echo "  ❌ shellcheck failed"
        FAILED=$((FAILED + 1))
    else
        echo "  ✓ shellcheck passed"
    fi

    echo
done < <(find "$SCRIPTS_DIR" -name "*.sh" -type f)

if [ $FAILED -eq 0 ]; then
    echo "=== All checks passed ==="
    exit 0
else
    echo "=== $FAILED check(s) failed ==="
    exit 1
fi
