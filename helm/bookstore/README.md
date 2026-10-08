# bookstore Helm chart

One chart deploys the full BookStore stack to **EKS**, **ROSA** or **on-prem OpenShift (MetalLB)**.
No Ingress controller and no OpenShift Route are needed: a bundled NGINX reverse proxy is the single entry point, exposed through a `LoadBalancer` Service.

```
           LoadBalancer Service "stateless-app"
     (AWS NLB on EKS/ROSA  |  MetalLB IP on-prem)
                         │
                ┌────────▼────────┐  ConfigMap: nginx.conf (routing)
                │  NGINX proxy    │
                └──┬──────┬─────┬─┘
            /      │ /shop│     │ /api
        ┌──────────▼┐ ┌───▼───┐ ┌▼────────┐   Job: rails db:migrate (hook)
        │  website  │ │ shopui│ │ shopapi │──┐
        └───────────┘ └───────┘ └─────────┘  │ ConfigMap + Secret
                                    ┌────────▼─────────┐
                                    │ MySQL StatefulSet│ PVC, ConfigMap (my.cnf), Secret
                                    └──────────────────┘
```

## Install

```bash
# EKS
helm upgrade --install bookstore ./helm/bookstore -n app1 --create-namespace -f ./helm/bookstore/values-eks.yaml

# ROSA
helm upgrade --install bookstore ./helm/bookstore -n app1 --create-namespace -f ./helm/bookstore/values-rosa.yaml

# On-prem OCP + MetalLB
helm upgrade --install bookstore ./helm/bookstore -n app1 --create-namespace -f ./helm/bookstore/values-ocp-metallb.yaml

# first install only: load demo data
#   add --set shopapi.seed.enabled=true
```

Then:

```bash
kubectl -n app1 get svc stateless-app      # wait for EXTERNAL-IP / hostname
curl http://<LB>:<port>/api/books
```

## Platform overlays

| File | LB | Service port → target | OpenShift mode | StorageClass |
|---|---|---|---|---|
| `values-eks.yaml` | AWS LB Controller, internal NLB, fixed subnets + private IPs | 6443 → 8080 | off | `gp3` |
| `values-rosa.yaml` | Same NLB annotations + `red-hat-managed=true` tag | 6443 → 8080 | on | `gp3-csi` |
| `values-ocp-metallb.yaml` | MetalLB pool `vrf-np-oss-pool-ipv4`, IP `10.106.5.136` | 8080 → 8080 | on | cluster default |

Change subnet IDs, private IPs, pool and IP per cluster. Keep environment-specific files (for example `values-rosa-prod.yaml`) next to these and layer them with extra `-f` flags.

## What `openshift.enabled=true` changes

* Fixed `runAsUser`/`runAsGroup`/`fsGroup` are removed from the NGINX and MySQL pods so `restricted-v2` assigns UIDs. NGINX uses `nginx-unprivileged` on 8080, and MySQL gets emptyDirs for `/var/run/mysqld` and `/tmp`.
* The upstream demo images (`website`, `shopui`, `shopapi`) run as root on port 80. Their dedicated ServiceAccount (`<release>-legacy`) is bound to the `anyuid` SCC (`openshift.legacyAppsAnyuid`). Set it to `false` once those images are rebuilt to run as non-root.

## Routing (replaces `route/ingress.yaml`)

The routes are defined in `values.yaml` and rendered into the `stateless-app` ConfigMap. Pods roll automatically when the config changes.

```yaml
proxy:
  routes:
    - { path: /api,  component: shopapi }
    - { path: /shop, component: shopui }
    - { path: /,     component: website }
    - { path: /legacy, upstream: "legacy.other-ns.svc:8080" }   # any backend
  config:
    clientMaxBodySize: 10m
    realIpFrom: ["10.153.0.0/16"]
    serverSnippet: |
      location = /robots.txt { return 200 "User-agent: *\nDisallow: /\n"; }
  customConfig: ""   # full nginx.conf override
```

## Database

* `database.enabled=true` (default) runs MySQL 5.7 as a StatefulSet. It has a headless and a client Service, a `volumeClaimTemplate` and a ConfigMap with the `my.cnf` fragment from `database.config`.
* Passwords are auto-generated on first install, then kept across upgrades through `lookup`. The Secret has `helm.sh/resource-policy: keep`.
  **With GitOps (Argo CD / Flux), set `database.auth.password`/`rootPassword` or `database.auth.existingSecret`.** `lookup` doesn't run there, so every sync would generate a new password.
* To use an external database such as RDS: set `database.enabled=false` and `externalDatabase.host`, plus either `password` or `existingSecret`.
* Schema migration runs as a `post-install,post-upgrade` hook Job, which waits for the DB first. The optional seed Job runs on `post-install` only.

## Other knobs

`global.imageRegistry` and `global.imagePullSecrets` (for private mirrors), `networkPolicy.enabled` (LB → proxy → apps → DB), `defaults.*` (nodeSelector/tolerations/affinity for every pod), and per-component `resources`, probes, `extraEnv` and `replicaCount`.
