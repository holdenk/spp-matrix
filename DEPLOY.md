# Deploy Guide: matrix-k8s

Step-by-step instructions for deploying the Matrix homeserver stack on K3s.

## Prerequisites

Verify these are running on your cluster before starting:

```bash
# K3s is healthy
kubectl get nodes

# Required operators/controllers
kubectl get pods -n cert-manager          # cert-manager
kubectl get pods -n metallb-system        # MetalLB
kubectl get pods -n cnpg-system           # CloudNativePG operator
kubectl get ingressclass                  # nginx ingress controller
kubectl get storageclass                  # local-path (default in K3s)
```

You also need:
- **DNS**: A records for `matrix.sparklingpinkpandas.com` and `dinner.sparklingpinkpandas.com` pointing to your MetalLB external IP
- **Backblaze B2**: A bucket created (e.g., `matrix-backup-sparklingpinkpandas`) with an application key
- A **ClusterIssuer** for Let's Encrypt (if you don't already have one):
  ```bash
  # Check existing issuers
  kubectl get clusterissuer
  # If none exist, create one (edit email first):
  # kubectl apply -f https://raw.githubusercontent.com/.../cert-issuer.yaml
  ```

## Phase 1: Namespace and Secrets

### 1.1 Create namespace

```bash
kubectl apply -f namespace.yaml
```

### 1.2 Create secrets

Copy each example and fill in real values:

```bash
# Tuwunel registration token + backup admin token
cp secrets/examples/tuwunel-secrets.example.yaml secrets/tuwunel-secrets.yaml
# Edit: set registration-token to output of `openssl rand -hex 32`
# Note: admin-token is populated later in Phase 3.4 (after creating admin user)

# Backblaze B2 credentials for backup sidecar
cp secrets/examples/rclone-secrets.example.yaml secrets/rclone-secrets.yaml
# Edit: set B2 key ID, app key, and bucket name

# Apply
kubectl apply -f secrets/tuwunel-secrets.yaml
kubectl apply -f secrets/rclone-secrets.yaml
```

> **Alternative:** Manage all secrets with Ansible Vault instead of manual copy-edit-apply.
> See [`ansible/README.md`](ansible/README.md) for instructions.

## Phase 2: Build and Push Backup Sidecar

Using the deploy script:

```bash
./scripts/deploy.sh YOUR_ORG
```

Or manually:

```bash
cd backup-sidecar
docker build -t ghcr.io/YOUR_ORG/tuwunel-backup-sidecar:latest .
docker push ghcr.io/YOUR_ORG/tuwunel-backup-sidecar:latest
cd ..
```

### Preflight Validation

Before deploying, run the predeploy checks to catch common issues:

```bash
./scripts/predeploy-check.sh
```

This checks for:
- **Errors**: Unresolved `CHANGE_ME_ORG` / `CHANGE_ME_NODE_HOSTNAME` placeholders in manifests
- **Warnings**: Mutable `:latest` image tags
- **YAML syntax**: Validates all manifest files (requires python3 + pyyaml)

Fix any errors before proceeding. Warnings are informational (`:latest` is expected for locally-built images).

## Phase 3: Deploy Tuwunel

### 3.1 Edit deployment

Open `tuwunel/deployment.yaml` and update:

1. **`nodeSelector`** — set `kubernetes.io/hostname` to your target node:
   ```bash
   kubectl get nodes -o wide  # pick a node
   ```

2. **Backup sidecar image** — replace `ghcr.io/CHANGE_ME_ORG/tuwunel-backup-sidecar:latest` with your actual image

### 3.2 Apply manifests

```bash
kubectl apply -f tuwunel/pvc.yaml
kubectl apply -f tuwunel/service.yaml
kubectl apply -f tuwunel/deployment.yaml
kubectl apply -f tuwunel/ingress-matrix.yaml
kubectl apply -f tuwunel/ingress-dinner.yaml
```

### 3.3 Verify

```bash
# Wait for pod to be ready
kubectl get pods -n matrix -l app.kubernetes.io/name=tuwunel -w

# Check logs
kubectl logs -n matrix -l app.kubernetes.io/name=tuwunel -c tuwunel

# Check backup sidecar
kubectl logs -n matrix -l app.kubernetes.io/name=tuwunel -c backup

# Wait for TLS certificates
kubectl get certificate -n matrix

# Test federation endpoint (may take a minute for cert to issue)
curl https://matrix.sparklingpinkpandas.com/_matrix/federation/v1/version

# Test well-known delegation
curl https://matrix.sparklingpinkpandas.com/.well-known/matrix/client
curl https://dinner.sparklingpinkpandas.com/.well-known/matrix/server
```

### 3.4 Create admin account and configure backup token

Open Element (app.element.io or desktop) and register:
1. Set homeserver to `matrix.sparklingpinkpandas.com`
2. Create account using the registration token you generated
3. This first account becomes your admin

Then obtain an access token for the backup sidecar:

```bash
# Log in as the admin user to get an access token
curl -s -X POST https://matrix.sparklingpinkpandas.com/_matrix/client/v3/login \
  -H 'Content-Type: application/json' \
  -d '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"YOUR_ADMIN_USERNAME"},"password":"YOUR_PASSWORD"}'
# Copy the "access_token" from the response
```

Update the tuwunel-secrets with the admin token:

```bash
# Edit secrets/tuwunel-secrets.yaml and set admin-token to the access_token value
kubectl apply -f secrets/tuwunel-secrets.yaml

# Restart the pod to pick up the new secret
kubectl rollout restart deploy/tuwunel -n matrix
```

The backup sidecar will not run backups until this token is set.

### 3.5 Create Spaces and rooms

In Element as admin:
1. Create Space: **Sparkling Pink Pandas**
   - Add rooms: `#general`, `#rides`, `#random`
2. Create Space: **Degenderates Dinner Club**
   - Add rooms: `#general`, `#recipes`, `#restaurants`
3. Create Space: **NRO** (optional, when ready)

## Phase 4: Discord Bridge (when ready)

### 4.1 Create bridge secrets

```bash
cp secrets/examples/mautrix-discord-db-credentials.example.yaml secrets/mautrix-discord-db-credentials.yaml
cp secrets/examples/mautrix-discord-secrets.example.yaml secrets/mautrix-discord-secrets.yaml

# Generate tokens
AS_TOKEN=$(openssl rand -hex 32)
HS_TOKEN=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -hex 32)

# Edit both files with the generated values
# The database-uri in mautrix-discord-secrets.yaml should use the DB_PASS

kubectl apply -f secrets/mautrix-discord-db-credentials.yaml
kubectl apply -f secrets/mautrix-discord-secrets.yaml
```

### 4.2 Deploy PostgreSQL

```bash
kubectl apply -f mautrix-discord/cnpg-cluster.yaml

# Wait for the database to be ready
kubectl get cluster -n matrix mautrix-discord-db -w
```

### 4.2.1 Configure PostgreSQL backups (recommended)

```bash
# Create pg-backup secret for CNPG backups to B2
cp secrets/examples/pg-backup-secrets.example.yaml secrets/pg-backup-secrets.yaml
# Edit: set B2 S3-compatible access key ID and secret access key

kubectl apply -f secrets/pg-backup-secrets.yaml
kubectl apply -f mautrix-discord/objectstore.yaml
kubectl apply -f mautrix-discord/scheduled-backup.yaml
```

The CNPG cluster manifest already includes the Barman Cloud plugin configuration
for WAL archiving. The ObjectStore defines the B2 destination and the ScheduledBackup
triggers daily base backups at 2:00 AM UTC.

Verify backup status:
```bash
kubectl get backup -n matrix
kubectl get scheduledbackup -n matrix
```

### 4.3 Deploy bridge

```bash
kubectl apply -f mautrix-discord/pvc.yaml
kubectl apply -f mautrix-discord/configmap.yaml
kubectl apply -f mautrix-discord/service.yaml
kubectl apply -f mautrix-discord/deployment.yaml
```

### 4.4 Register appservice

```bash
# Extract the generated registration.yaml
kubectl exec deploy/mautrix-discord -n matrix -- cat /data/registration.yaml
```

In Element, go to `#admins:sparklingpinkpandas.com` and run:
```
!admin appservices register
```
Then paste the contents of `registration.yaml`.

Verify:
```
!admin appservices list
```

### 4.5 Connect Discord

1. Go to https://discord.com/developers/applications and create a new application
2. Create a bot, copy the token
3. Invite the bot to your Discord server with appropriate permissions
4. In Matrix, DM `@discordbot:sparklingpinkpandas.com` with `!discord login`
5. Follow the prompts to link your Discord account

## Phase 5: Event Bot (when iCal feed is ready)

### 5.1 Create bot user

In the Tuwunel admin room:
```
!admin users create @event-bot:sparklingpinkpandas.com SomePassword
```

Log in as `@event-bot` from Element to get an access token, or use the API:
```bash
curl -X POST https://matrix.sparklingpinkpandas.com/_matrix/client/v3/login \
  -H 'Content-Type: application/json' \
  -d '{"type":"m.login.password","user":"event-bot","password":"SomePassword"}'
```

### 5.2 Create secret and deploy

```bash
cp secrets/examples/event-bot-secrets.example.yaml secrets/event-bot-secrets.yaml
# Edit: set MATRIX_ACCESS_TOKEN from the login response

kubectl apply -f secrets/event-bot-secrets.yaml
```

Edit `event-bot/configmap.yaml`:
- Set `FEED_URL` to the actual iCal feed URL
- Set `MATRIX_ROOM_ID` to the `#rides` room ID (find it in Element room settings)

Edit `event-bot/deployment.yaml`:
- Set the container image to your built bot image

```bash
kubectl apply -f event-bot/pvc.yaml
kubectl apply -f event-bot/configmap.yaml
kubectl apply -f event-bot/deployment.yaml
```

### 5.3 Verify

```bash
kubectl logs -n matrix -l app.kubernetes.io/name=spp-event-bot -f
```

You should see periodic feed polls and event posts.

## Backup Verification

### How backups work

The backup sidecar runs alongside tuwunel in the same pod. Every 6 hours it:
1. Calls the tuwunel admin API to trigger `!admin server backup_database`
2. Waits for the consistent RocksDB snapshot to be written to `/data/backup/`
3. Uploads the RocksDB snapshot to B2 at `{bucket}/tuwunel/backup/`
4. Uploads media files from `/data/db/media/` to B2 at `{bucket}/tuwunel/media/`

Backups will not run until the `admin-token` is set in `tuwunel-secrets` (see Phase 3.4).

### Check backup status

```bash
# Check sidecar logs for backup status
kubectl logs -n matrix -l app.kubernetes.io/name=tuwunel -c backup

# Verify data exists in B2 (requires rclone locally)
rclone ls b2:matrix-backup-sparklingpinkpandas/tuwunel/backup/ --config your-rclone.conf
rclone ls b2:matrix-backup-sparklingpinkpandas/tuwunel/media/ --config your-rclone.conf
```

### Manual restore

Restore is a manual process:

1. Scale down: `kubectl scale deploy tuwunel -n matrix --replicas=0`
2. Copy backup data from B2 to the PVC (e.g., via a debug pod or local rclone):
   ```bash
   rclone copy b2:matrix-backup-sparklingpinkpandas/tuwunel/backup/ /path/to/pvc/backup/ --config your-rclone.conf
   rclone copy b2:matrix-backup-sparklingpinkpandas/tuwunel/media/ /path/to/pvc/db/media/ --config your-rclone.conf
   ```
3. Follow the [tuwunel restore procedure](https://github.com/matrix-construct/tuwunel/blob/main/docs/maintenance.md) to reconstruct the database from the backup files
4. Scale up: `kubectl scale deploy tuwunel -n matrix --replicas=1`

## Inviting Users

Share the registration token with people you want to invite, along with a link to the setup guide website. They will:
1. Visit the website for their platform's setup guide
2. Download Element
3. Set homeserver to `matrix.sparklingpinkpandas.com`
4. Create an account using the registration token
5. Join the appropriate Space

## Troubleshooting

| Issue | Solution |
|---|---|
| Pod stuck Pending | Check `kubectl describe pod` — likely a nodeSelector mismatch or PVC issue |
| TLS cert not issuing | Check `kubectl describe certificate -n matrix` and cert-manager logs |
| Can't register | Verify the registration token secret is correct and Tuwunel picked it up |
| Bridge not connecting | Check bridge logs, verify appservice is registered, check network policies |
| Backup failing | Check sidecar logs, verify B2 credentials in the rclone secret and admin-token in tuwunel-secrets |
