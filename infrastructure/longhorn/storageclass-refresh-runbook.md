# Longhorn StorageClass Refresh

**Goal:** apply immutable spec changes by deleting the live class and letting ArgoCD recreate it.

## Prep
- Confirm manifests in `infrastructure/longhorn/` and ADR 0007 show the desired spec.
- Ensure you can `kubectl delete storageclass <name>`.
- Consider a brief freeze on new PVC creation (default class is unavailable during the gap).

## Steps
1. (Optional) Pause Argo auto-sync if you want manual timing.
2. Delete the classes:
   ```
   kubectl delete storageclass replicated
   kubectl delete storageclass single-replica
   kubectl delete storageclass ephemeral
   ```
   Existing PVs stay Bound; only new PVCs pause.
3. Let Argo resync (auto or manual). If needed, `kubectl apply -f infrastructure/longhorn/<file>.yaml`.
4. Re-enable auto-sync if you paused it.

## Verify
- `kubectl get storageclass`
- `kubectl get pv -A --sort-by=.spec.storageClassName`
- `kubectl apply --dry-run=server -f infrastructure/longhorn/storageclass-replicated.yaml`
- ArgoCD UI shows Healthy/Synced

## References
- ADR 0007 – [Longhorn StorageClass Strategy](../../adr/0007-longhorn-storageclass-strategy.md)
- Kubernetes – [PersistentVolume lifecycle](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim)
- Kubernetes – [StorageClass validation code](https://github.com/kubernetes/kubernetes/blob/v1.30.0/pkg/apis/storage/validation/validation.go#L66-L86)
- Longhorn – [Storage-class parameters](https://longhorn.io/docs/1.10.0/references/storage-class-parameters/)
