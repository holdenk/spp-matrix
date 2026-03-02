# Ansible Vault Secrets Management (Alternative Method)

This directory provides an **alternative** to the manual `kubectl apply` workflow
described in the main [DEPLOY.md](../DEPLOY.md). Instead of copying `.example.yaml`
files and editing them by hand, you encrypt your secrets in an Ansible vault and
use a playbook to template and apply them.

## Prerequisites

- Ansible 2.14+ (`pip install ansible`)
- `kubectl` configured with access to your K3s cluster
- The `kubernetes.core` collection:
  ```bash
  ansible-galaxy collection install kubernetes.core
  ```

## Quick Start

1. Copy the example vault vars file:
   ```bash
   cp vault-vars.example.yml vault-vars.yml
   ```

2. Fill in all the `CHANGE_ME` values with real credentials

3. Encrypt the file:
   ```bash
   ansible-vault encrypt vault-vars.yml
   ```

4. Run the playbook:
   ```bash
   ansible-playbook playbook.yaml --ask-vault-pass
   ```

## What It Does

The playbook templates Kubernetes Secret manifests from your vault variables and
applies them to the `matrix` namespace. It covers all six secrets this project needs:

| Secret | Purpose |
|---|---|
| `tuwunel-secrets` | Registration token |
| `rclone-secrets` | Backblaze B2 credentials for Tuwunel backup |
| `mautrix-discord-db-credentials` | PostgreSQL username/password |
| `mautrix-discord-secrets` | Bridge tokens and database URI |
| `event-bot-secrets` | Bot access token |
| `pg-backup` | S3 credentials for CNPG PostgreSQL backup |

## Editing Encrypted Vars

```bash
ansible-vault edit vault-vars.yml
```

## What Encrypted Vault Looks Like

After `ansible-vault encrypt`, the file becomes opaque ciphertext:

```
$ANSIBLE_VAULT;1.1;AES256
62313365396662343061393464336163383764316462
3661626231633033303861343333643038313339613562
6232646432393833340a653031366231653666316138
...
```

The original structure (before encryption) is shown in `vault-vars.example.yml`.
