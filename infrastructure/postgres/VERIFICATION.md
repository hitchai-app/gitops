# Verification guide

Use the commands below after ArgoCD syncs the CloudNativePG applications.

## 1. Operator status

```bash
kubectl get pods -n cnpg-system
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg --tail=50
```

All pods should be `Running`.

## 2. Cluster health

```bash
# Check CloudNativePG custom resource
kubectl get clusters.postgresql.cnpg.io -n postgres-prod
kubectl describe cluster postgres-shared -n postgres-prod

# Check PostgreSQL pod
kubectl get pods -n postgres-prod
```

`postgres-shared` should report `Cluster in healthy state` and the pod should be ready.

## 3. Storage

```bash
kubectl get pvc -n postgres-prod
```

Expect a bound PVC using the `longhorn-single-replica` storage class with 50 GiB capacity.

## 4. Backups

```bash
kubectl get secret backup-s3-credentials -n postgres-prod
kubectl get cluster postgres-shared -n postgres-prod -o jsonpath='{.status.firstRecoverabilityPoint}'
```

The secret must exist, and once the first backup completes the cluster status exposes a recoverability point. You can also inspect the S3 bucket via your cloud CLI.

## 5. Metrics

```bash
kubectl get podmonitor -n postgres-prod
```

A PodMonitor named `postgres-shared` should be present so Prometheus can scrape metrics.

## 6. ArgoCD Applications

```bash
kubectl get application cloudnativepg -n argocd
kubectl get application postgres-prod -n argocd
```

Both Applications should be `Synced` and `Healthy`.

## 7. Disaster recovery smoke test (optional)

To validate backups end-to-end:

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restore-test
  namespace: postgres-prod
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.2
  storage:
    storageClass: longhorn-single-replica
    size: 10Gi
  bootstrap:
    recovery:
      source: postgres-shared
  externalClusters:
  - name: postgres-shared
    barmanObjectStore:
      destinationPath: s3://cloudnativepg-backups/postgres-prod
      s3Credentials:
        accessKeyId:
          name: backup-s3-credentials
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: backup-s3-credentials
          key: ACCESS_SECRET_KEY
      wal:
        compression: gzip
YAML
```

Wait for the cluster to become healthy, verify data, then remove it:

```bash
kubectl delete cluster postgres-restore-test -n postgres-prod
```

This confirms that PITR/backup configuration is functional.
