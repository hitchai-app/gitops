# 0009. Secrets Management Strategy

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need to manage secrets for infrastructure services:
- External credentials (Cloudflare API, AWS S3)
- Bootstrap secrets (ArgoCD GitHub token)
- Database passwords (PostgreSQL, Redis)
- Application credentials (MinIO root)

Requirements:
- GitOps-compatible where appropriate
- Minimal operational overhead
- Small team (developers handle ops)

## Decision

**Two-tier strategy:**

1. **Operators auto-generate** internal secrets (PostgreSQL, Redis passwords) - Not in Git
2. **Sealed Secrets** for external/bootstrap credentials - Encrypted in Git

**No Vault.** Complexity not justified.

## Alternatives Considered

### 1. SOPS
- **Pros**: Fine-grained encryption, multi-cloud KMS
- **Cons**: Requires ArgoCD plugin, manual encryption, key management complexity
- **Why not chosen**: Plugin overhead vs Sealed Secrets simplicity

### 2. Vault + External Secrets Operator
- **Pros**: Dynamic secrets, auto-rotation, audit trail, centralized management
- **Cons**:
  - Vault cluster (3+ nodes), unsealing, policies = ~20-40h setup, ~5-10h/month maintenance
  - ESO project health concerns (maintainers paused releases Aug 2025)
- **Why not chosen**: Massive overkill for small team with static secrets

### 3. Plain Secrets in Git
- **Pros**: Simplest
- **Cons**: Security risk
- **Why not chosen**: Unacceptable

## Consequences

### Positive
- ✅ Simple: Two clear categories (auto vs sealed)
- ✅ No external dependencies (Vault, KMS)
- ✅ ArgoCD native (no plugins)
- ✅ Operators handle most secrets automatically

### Negative
- ❌ No dynamic secrets or auto-rotation
- ❌ Limited audit (Git commits only)
- ⚠️ Must backup Sealed Secrets private key

### Neutral
- Migration to Vault possible if needs change
- Sealed Secrets actively maintained (v0.32.2 Sept 2025)

## How It Works

### Tier 1: Auto-Generated (Operators)

**Examples:** PostgreSQL password, Redis password

**Process:**
- CloudNativePG/Helm generates random password on install
- Stores as Kubernetes Secret in cluster
- Apps read from Secret
- **Not in Git** - operators recreate on cluster rebuild

**No rotation needed** (internal passwords, strong random once is sufficient)

---

### Tier 2: Sealed Secrets (External/Bootstrap)

**Examples:** Cloudflare API token, AWS S3 credentials, ArgoCD GitHub token

**How Sealed Secrets works:**

1. Controller generates RSA key pair on install
   - Private key: Stored as Secret in cluster (`kube-system` namespace)
   - Public key: Fetchable by users

2. Encrypt locally with `kubeseal` CLI:
   ```bash
   kubeseal --fetch-cert > pub.pem
   kubectl create secret generic cloudflare-api-token \
     --from-literal=api-token=xxx \
     --dry-run=client -o yaml | \
     kubeseal --cert pub.pem > sealed-secret.yaml
   ```

3. Commit encrypted `SealedSecret` to Git (safe)

4. ArgoCD syncs to cluster

5. Controller decrypts with private key → creates plain `Secret`

**Security model:**
- Protects secrets in Git (encrypted)
- Does NOT protect from cluster admins (can read private key Secret)
- Private key is the "master key" - must backup externally

**Rotation:** Annually or when compromised (re-seal and commit)

## Critical: Private Key Backup

```bash
# Backup immediately after install
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml

# Store encrypted externally (1Password, S3, etc.)
# NOT in Git
```

**Key loss = disaster:** All SealedSecrets become undecryptable, must re-encrypt everything

## Disaster Recovery

**Auto-generated secrets:**
- Recreate cluster from Git → operators regenerate
- RTO: < 1 hour

**Sealed Secrets:**
1. Restore Sealed Secrets controller
2. Restore private key from backup
3. Restart controller
4. ArgoCD syncs SealedSecrets → controller decrypts
- RTO: < 30 minutes

## When to Add Vault

**Add when:**
- Team > 20 people
- Compliance requires dynamic secrets or detailed audit
- Multiple clusters need centralized management
- Need temporary credentials

**Don't add now** - wait for actual pain

## References

- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets)
- [CloudNativePG Bootstrap](https://cloudnative-pg.io/documentation/current/bootstrap/)
- [Vault Use Cases](https://www.vaultproject.io/use-cases)
