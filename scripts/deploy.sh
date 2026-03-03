#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLATFORM=${PLATFORM:-linux/amd64,linux/arm64}

usage() {
    cat <<EOF
Usage: $(basename "$0") <org> [--apply]

Build and push the backup sidecar image, with optional cluster deployment.

Arguments:
  <org>       Docker org

Options:
  --apply     Run predeploy checks then kubectl apply core manifests
  -h, --help  Show this help message

Examples:
  $(basename "$0") myorg              # Build and push image only
  $(basename "$0") myorg --apply      # Build, push, check, and deploy
EOF
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

ORG=""
APPLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --apply)   APPLY=true; shift ;;
        -*)        echo "Unknown option: $1" >&2; usage ;;
        *)
            if [[ -z "$ORG" ]]; then
                ORG="$1"; shift
            else
                echo "Unexpected argument: $1" >&2; usage
            fi
            ;;
    esac
done

if [[ -z "$ORG" ]]; then
    usage
fi

IMAGE="${ORG}/tuwunel-backup-sidecar:latest"

echo "==> Building ${IMAGE}"
docker buildx build --platform "${PLATFORM}" -t "$IMAGE" "$REPO_ROOT/backup-sidecar" --push

echo "==> Image pushed successfully"

if [[ "$APPLY" == true ]]; then
    echo ""
    echo "==> Running predeploy checks"
    "$SCRIPT_DIR/predeploy-check.sh"

    echo ""
    echo "==> Applying core manifests"
    kubectl apply -f "$REPO_ROOT/namespace.yaml"
    kubectl apply -f "$REPO_ROOT/tuwunel/"
    kubectl apply -f "$REPO_ROOT/event-bot/"

    echo ""
    echo "==> Core manifests applied"
    echo ""
    echo "NOTE: mautrix-discord requires manual deployment after CNPG is ready:"
    echo "  kubectl apply -f mautrix-discord/cnpg-cluster.yaml"
    echo "  kubectl wait --for=condition=Ready cluster/mautrix-discord-db -n matrix --timeout=120s"
    echo "  kubectl apply -f mautrix-discord/"
fi
