# Implementation summary

```
infrastructure/postgres/
├── base/
│   ├── cluster.yaml                # Canonical CloudNativePG cluster spec
│   └── kustomization.yaml
├── overlays/
│   └── prod/
│       ├── backup-s3-credentials-sealed.yaml.example
│       └── kustomization.yaml
├── README.md
├── IMPLEMENTATION.md
└── VERIFICATION.md
```

## Base cluster (`base/cluster.yaml`)

- `imageName`: `ghcr.io/cloudnative-pg/postgresql:17.2`
- `instances`: 1 (single node to start; CloudNativePG handles replicas later)
- `storage`: `longhorn-single-replica`, 50 GiB
- `resources`: requests 500 m CPU / 1 Gi RAM, limits 2 CPU / 2 Gi RAM
- `monitoring`: PodMonitor enabled
- `backup`: Barman to `s3://cloudnativepg-backups/postgres-prod`, gzip compression, 30 day retention
- `bootstrap`: creates an `app` database owned by `app`

Secrets are referenced as `backup-s3-credentials` (to be provided via SealedSecret).

## Production overlay (`overlays/prod`)

- Applies the base manifest into namespace `postgres-prod`
- Provides `.example` sealed secret and instructs the operator to add the sealed secret file once generated
- No further patches are required; base spec already matches production sizing

## ArgoCD integration

- Operator is deployed by `apps/infrastructure/cloudnativepg.yaml`
- The production cluster is managed via `apps/infrastructure/postgres.yaml`
- Both Applications use automated sync with prune + self-heal and `CreateNamespace=true`
