# Bookstore via ACM + OpenShift GitOps

Apply on the ACM hub (OpenShift GitOps installed in `openshift-gitops`):

```
oc apply -k argocd
```

| File | Purpose |
|---|---|
| `managedclustersetbinding.yaml` | Binds the `global` ClusterSet into `openshift-gitops` |
| `placement.yaml` | Picks managed clusters with `vendor` in `OpenShift`/`EKS` (excludes `local-cluster`) |
| `gitopscluster.yaml` | Registers those clusters in Argo CD; cluster secrets inherit the ManagedCluster labels |
| `applicationset.yaml` | One `bookstore-<cluster>` app per cluster, values file chosen from labels |

Values file selection (ACM sets `vendor` and `cloud` automatically):

| `vendor` | `cloud` | Values file |
|---|---|---|
| `EKS` | any | `values-eks.yaml` |
| `OpenShift` | `Amazon` | `values-rosa.yaml` |
| `OpenShift` | not `Amazon`/`Azure`/`Google`/`IBM` (e.g. `BareMetal`, `VSphere`, `Other`) | `values-ocp-metallb.yaml` |

Check what a cluster will get:

```
oc get managedclusters -L vendor,cloud
oc get secret -n openshift-gitops -l apps.open-cluster-management.io/acm-cluster=true --show-labels
oc get applications -n openshift-gitops -l app.kubernetes.io/part-of=bookstore -L bookstore/platform
```

Notes:
- The values files hold per-cluster subnets / IPs (NLB subnets, MetalLB IP). With more than one cluster
  per platform, move those into a per-cluster file or override them in the ApplicationSet.
- Set `database.auth.existingSecret` (or fixed passwords) for GitOps: Helm `lookup` doesn't run under
  Argo CD, so the generated DB password would change on every sync.
