#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0
WARNINGS=0

error() {
    echo "ERROR: $1" >&2
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo "WARNING: $1" >&2
    WARNINGS=$((WARNINGS + 1))
}

MANIFEST_DIRS=("tuwunel" "mautrix-discord" "event-bot" "matrix-site")
MANIFEST_FILES=("namespace.yaml")

# --- Check for unresolved placeholders ---
echo "==> Checking for unresolved placeholders"

for dir in "${MANIFEST_DIRS[@]}"; do
    target="$REPO_ROOT/$dir"
    if [[ ! -d "$target" ]]; then
        continue
    fi
    while IFS= read -r file; do
        while IFS= read -r match; do
            error "$file: unresolved placeholder: $match"
        done < <(grep -n 'CHANGE_ME_ORG\|CHANGE_ME_NODE_HOSTNAME\|CHANGE_ME' "$file" || true)
    done < <(find "$target" -name '*.yaml' -type f -not -path '*/examples/*')
done

for file in "${MANIFEST_FILES[@]}"; do
    target="$REPO_ROOT/$file"
    if [[ ! -f "$target" ]]; then
        continue
    fi
    while IFS= read -r match; do
        error "$target: unresolved placeholder: $match"
    done < <(grep -n 'CHANGE_ME_ORG\|CHANGE_ME_NODE_HOSTNAME\|CHANGE_ME' "$target" || true)
done

# --- Check for mutable :latest tags ---
echo "==> Checking for mutable :latest image tags"

for dir in "${MANIFEST_DIRS[@]}"; do
    target="$REPO_ROOT/$dir"
    if [[ ! -d "$target" ]]; then
        continue
    fi
    while IFS= read -r file; do
        while IFS= read -r match; do
            warn "$file: mutable :latest tag: $match"
        done < <(grep -n 'image:.*:latest' "$file" || true)
    done < <(find "$target" -name '*.yaml' -type f)
done

# --- Optional YAML syntax validation ---
echo "==> Checking YAML syntax"

if python3 -c "import yaml" 2>/dev/null; then
    for dir in "${MANIFEST_DIRS[@]}"; do
        target="$REPO_ROOT/$dir"
        if [[ ! -d "$target" ]]; then
            continue
        fi
        while IFS= read -r file; do
            if ! python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    list(yaml.safe_load_all(f))
" "$file" 2>/dev/null; then
                error "$file: invalid YAML syntax"
            fi
        done < <(find "$target" -name '*.yaml' -type f)
    done

    for file in "${MANIFEST_FILES[@]}"; do
        target="$REPO_ROOT/$file"
        if [[ ! -f "$target" ]]; then
            continue
        fi
        if ! python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    list(yaml.safe_load_all(f))
" "$target" 2>/dev/null; then
            error "$target: invalid YAML syntax"
        fi
    done
else
    echo "  (skipped — python3 with pyyaml not available)"
fi

# --- Summary ---
echo ""
echo "==> Preflight summary: ${ERRORS} error(s), ${WARNINGS} warning(s)"

if [[ "$ERRORS" -gt 0 ]]; then
    exit 1
fi
