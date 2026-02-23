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
# Tuwunel registration token
cp secrets/examples/tuwunel-secrets.example.yaml secrets/tuwunel-secrets.yaml
# Edit: set registration-token to output of `openssl rand -hex 32`

# Backblaze B2 credentials for backup sidecar
cp secrets/examples/rclone-secrets.example.yaml secrets/rclone-secrets.yaml
# Edit: set B2 key ID, app key, and bucket name

# Apply
kubectl apply -f secrets/tuwunel-secrets.yaml
kubectl apply -f secrets/rclone-secrets.yaml
```

## Phase 2: Build and Push Backup Sidecar

```bash
cd backup-sidecar
docker build -t ghcr.io/YOUR_ORG/tuwunel-backup-sidecar:latest .
docker push ghcr.io/YOUR_ORG/tuwunel-backup-sidecar:latest
cd ..
```

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

### 3.4 Create admin account

Open Element (app.element.io or desktop) and register:
1. Set homeserver to `matrix.sparklingpinkpandas.com`
2. Create account using the registration token you generated
3. This first account becomes your admin

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
kubectl apply -f event-bot/configmap.yaml
kubectl apply -f event-bot/deployment.yaml
```

### 5.3 Verify

```bash
kubectl logs -n matrix -l app.kubernetes.io/name=spp-event-bot -f
```

You should see periodic feed polls and event posts.

## Backup Verification

### Manual backup test

```bash
# Check sidecar logs for backup status
kubectl logs -n matrix -l app.kubernetes.io/name=tuwunel -c backup

# Verify data exists in B2 (requires rclone locally)
rclone ls b2:matrix-backup-sparklingpinkpandas/tuwunel/ --config your-rclone.conf
```

### Restore test

To verify restore works:
1. Scale down: `kubectl scale deploy tuwunel -n matrix --replicas=0`
2. Delete the PVC data (or create a fresh PVC)
3. Scale up: `kubectl scale deploy tuwunel -n matrix --replicas=1`
4. Watch the sidecar logs — it should detect the empty directory and restore from B2

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
| Backup failing | Check sidecar logs, verify B2 credentials in the rclone secret |
