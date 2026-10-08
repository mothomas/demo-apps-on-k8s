# Bookstore via ACM + OpenShift GitOps (pull model)

Apply on the ACM hub:

```
oc apply -k argocd
```

| File | Purpose |
|---|---|
| `managedclustersetbinding.yaml` | Binds the `global` ClusterSet into `openshift-gitops` |
| `placement.yaml` | `placement-bookstore`: managed clusters labelled `bookstore=true` |
| `gitopscluster.yaml` | Registers those clusters with the hub Argo CD |
| `applicationset.yaml` | One `bookstore-<cluster>` Application per selected cluster, pulled and synced by the cluster's own Argo CD |

## Add a cluster

1. Create `helm/bookstore/values-<cluster-name>.yaml` (the ManagedCluster name). Copy the closest
   platform file (`values-eks.yaml`, `values-rosa.yaml`, `values-ocp-metallb.yaml`) and set that
   cluster's subnets / IPs / storageClass. Commit and push.
2. Label the cluster:
   ```
   oc label managedcluster <cluster-name> bookstore=true
   ```

Argo CD renders the chart with `values.yaml` then `values-<cluster-name>.yaml`. If the per-cluster
file is missing the sync fails rather than deploying defaults.

Remove the label to remove the app from that cluster.

## Notes
- Set `database.auth.existingSecret` (or fixed passwords) in each cluster file: Helm `lookup` doesn't
  run under Argo CD, so a generated DB password would change on every sync.
- The pull model needs OpenShift GitOps on each managed cluster and the ACM Argo CD pull integration
  enabled (the same setup your existing `aws-poc-pull-model-apps` ApplicationSet uses).
