#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT="$REPO_ROOT/matrix-site/index.html"
OUTPUT="$REPO_ROOT/matrix-site/configmap.yaml"

if [[ ! -f "$INPUT" ]]; then
    echo "ERROR: $INPUT not found" >&2
    exit 1
fi

# Indent each line of the HTML by 4 spaces for YAML block scalar,
# but leave blank lines empty to match standard YAML style.
INDENTED=$(sed '/^$/!s/^/    /; /^$/s/^//' "$INPUT")

cat > "$OUTPUT" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: matrix-site-content
  namespace: matrix
  labels:
    app.kubernetes.io/name: matrix-site
data:
  index.html: |
${INDENTED}
EOF

echo "Generated $OUTPUT from $INPUT"
