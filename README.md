# Matrix K8s - Sparkling Pink Pandas & Friends

Kubernetes manifests for deploying a [Tuwunel](https://github.com/matrix-construct/tuwunel) Matrix homeserver with a Discord bridge and event bot.

## Components

- **Tuwunel** — Rust-based Matrix homeserver with backup sidecar
- **mautrix-discord** — Discord bridge for Matrix
- **SPP Event Bot** — Posts events from an iCal feed to the #rides channel
- **Backup Sidecar** — Automatic backup to Backblaze B2 with restore-on-empty

## Communities

Three Matrix Spaces on a single homeserver (`sparklingpinkpandas.com`):

- **Sparkling Pink Pandas (SPP)** — `matrix.sparklingpinkpandas.com`
- **Degenderates Dinner Club** — `dinner.sparklingpinkpandas.com` (delegates to same server)
- **NRO** — (future, Discord bridge first use case)

## Prerequisites

- K3s cluster with:
  - MetalLB (LoadBalancer IPs)
  - cert-manager (TLS certificates)
  - CNPG operator (PostgreSQL for Discord bridge)
  - nginx ingress controller
  - local-path-provisioner (default in K3s)
- DNS A records pointing to MetalLB IP:
  - `matrix.sparklingpinkpandas.com`
  - `dinner.sparklingpinkpandas.com`
- Backblaze B2 bucket for backups

## Deployment

### 1. Create namespace and secrets

```bash
kubectl apply -f namespace.yaml

# Copy and fill in secret examples
cp secrets/examples/tuwunel-secrets.example.yaml secrets/tuwunel-secrets.yaml
cp secrets/examples/rclone-secrets.example.yaml secrets/rclone-secrets.yaml
# Edit the files with real values, then:
kubectl apply -f secrets/
```

### 2. Build and push the backup sidecar

```bash
./scripts/deploy.sh YOUR_ORG
```

### 3. Deploy Tuwunel

Edit `tuwunel/deployment.yaml` — set `nodeSelector` hostname and backup sidecar image.

```bash
kubectl apply -f tuwunel/
kubectl apply -f matrix-site/configmap.yaml
kubectl apply -f matrix-site/deployment.yaml
kubectl apply -f matrix-site/service.yaml
```

Verify:
```bash
curl https://matrix.sparklingpinkpandas.com/_matrix/federation/v1/version
```

### 4. Create admin account

The first user registers using the invite code in Cinny Web (`https://app.cinny.in/#/register`) against `matrix.sparklingpinkpandas.com`. If someone needs an invite code, direct them to email `info@sparklingpinkpandas.com` or ask someone already on the server for an introduction. After account setup, they can use their preferred phone client. Then create Spaces and rooms via the admin room (`#admins:sparklingpinkpandas.com`).

### 5. Deploy Discord bridge (when ready)

```bash
# Create DB credentials secret first
kubectl apply -f secrets/mautrix-discord-db-credentials.yaml
kubectl apply -f mautrix-discord/cnpg-cluster.yaml

# Wait for CNPG to be ready
kubectl wait --for=condition=Ready cluster/mautrix-discord-db -n matrix --timeout=120s

# Deploy bridge
kubectl apply -f secrets/mautrix-discord-secrets.yaml
kubectl apply -f mautrix-discord/

# Extract and register appservice
kubectl exec deploy/mautrix-discord -n matrix -- cat /data/registration.yaml
# Paste into Tuwunel admin room: !admin appservices register
```

### 6. Deploy event bot (when iCal feed is ready)

```bash
kubectl apply -f secrets/event-bot-secrets.yaml
kubectl apply -f event-bot/
```

## Scripts

- **`scripts/deploy.sh <org>`** — Build and push the backup sidecar image. Pass `--apply` to also run predeploy checks and `kubectl apply` core manifests.
- **`scripts/predeploy-check.sh`** — Preflight validation: checks for unresolved placeholders, mutable `:latest` tags, and YAML syntax errors.

## Directory Structure

```
├── ansible/                 # Ansible Vault alternative for secrets management
├── backup-sidecar/          # Backup/restore sidecar container
├── tuwunel/                 # Homeserver deployment manifests
├── mautrix-discord/         # Discord bridge + CNPG database manifests
│   ├── objectstore.yaml     #   Barman Cloud backup to B2
│   └── scheduled-backup.yaml#   Daily base backup schedule
├── event-bot/               # Event bot manifests
├── matrix-site/             # Signup site content + Kubernetes manifests
├── scripts/                 # Deploy and validation scripts
├── secrets/examples/        # Secret templates (fill in and apply)
└── namespace.yaml
```

## Related Repos

- **spp-event-bot** — Go bot source code
