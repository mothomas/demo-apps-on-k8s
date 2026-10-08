# Demo Application: BookStore App services on K8S 

Follows micro-services approach. Run locally using docker-compose and traefik as loadbalancer/proxy; and on Kubernetes (DigitalOcean Managed).

> ## Announcement: Course on Kubernetes
> If you're want to start deploying your containers to Kubernetes, especially on AWS EKS, [check this course on Kubernetes](https://courses.devteds.com/kubernetes-get-started) that walkthrough creating Kubernetes cluster on AWS EKS using Terraform and deploying multiple related containers applications to Kubernetes and more. https://courses.devteds.com/kubernetes-get-started

![DemoStoreAppArchitecture](https://github.com/devteds/demo-app-bookstore/blob/master/doc/demo-app-architecture.png)

## Code directory

```
mkdir -p ~/proj
cd ~/proj
git clone git@github.com:devteds/demo-apps-on-k8s.git
```

## Run locally

```
cd ~/proj/demo-apps-on-k8s/local

# one time
docker network create demoapp

docker-compose up
# on a separate terminal window
docker-compose ps
```

Once `shopapi` is up, run schema migration script and seed some test data

```
docker-compose exec shopapi rails db:migrate
docker-compose exec shopapi rails db:seed
```

Once all the services start up,

```
open http://localhost
```

- http://localhost => routes to `website` service
- Clicking on `Shop` goes to http://localhost/shop => routes to `shopui` service
- Shopping page calls http://localhost/api/books => routes to `shopapi` service


**Note:** You may change the port mapping if port 80 is taken on dev machine


## Deploy with Helm (EKS / ROSA / on-prem OpenShift)

The whole stack is a single Helm chart at [`helm/bookstore`](helm/bookstore/README.md). It includes website, shopui, shopapi, a MySQL StatefulSet, the DB migration Job and an NGINX reverse proxy.
The Ingress controller and the Ingress/Route objects are gone. NGINX routes `/`, `/shop` and `/api` from a ConfigMap and is exposed by a `LoadBalancer` Service: an AWS NLB on EKS/ROSA, MetalLB on-prem.

```
# EKS
helm upgrade --install bookstore ./helm/bookstore -n app1 --create-namespace -f ./helm/bookstore/values-eks.yaml
# ROSA
helm upgrade --install bookstore ./helm/bookstore -n app1 --create-namespace -f ./helm/bookstore/values-rosa.yaml
# On-prem OCP + MetalLB
helm upgrade --install bookstore ./helm/bookstore -n app1 --create-namespace -f ./helm/bookstore/values-ocp-metallb.yaml
```

### Multi-cluster with ACM + Argo CD

`argocd/` has an ACM pull-model ApplicationSet: label a managed cluster `bookstore=true` and it gets the chart with `helm/bookstore/values-<cluster-name>.yaml`. See [argocd/README.md](argocd/README.md).

The raw manifests under `services/` and the steps below are kept for reference and learning.

## On Kubernetes (manual, step by step)

Create Kubernetes cluster on DigitalOcean

### DigitalOcean API Token

Signup/Login to DigitalOcean and genereate API Token

### Create Kubernetes Cluster

```
cd ~/proj/demo-apps-on-k8s/infra
cp secret.auto.example.tfvars secret.auto.tfvars
# edit to assign DigitalOcean API token and save
```

Optionally edit `main.tf` as needed. For example, if you need to change the region or number of worker nodes or kubernetes version

```
terraform init
terraform plan
terraform apply
```

You may login to DigitalOcean and verify Kubernetes status.

Update `kubeconfig` for `kubectl`

```
mkdir -p ~/.kube
terraform output config > ~/.kube/config
```

Verify Kubernetes cluster status

```
kubectl get nodes
kubectl version
# this must give you both client and server version. Client is kubectl. Server is K8S api server
```

### Service 1: Website

```
cd ~/proj/demo-apps-on-k8s

kubectl apply -f services/website/deploy.yaml
kubectl get deploy
kubectl get po

kubectl apply -f services/website/service.yaml
kubectl get svc
kubectl describe svc/website
```

Verify using port-forward

```
kubectl port-forward svc/website 8082:80
open http://localhost:8082
```

### Service 2: Shopping API

Install database

```
helm install bookstore stable/mysql --set mysqlUser=appuser,mysqlPassword=appuser123,mysqlDatabase=bookstore

kubectl get  svc -l app=bookstore-mysql
kubectl get  po -l app=bookstore-mysql
kubectl get  deploy -l app=bookstore-mysql
```

Verify

```
kubectl run -i --tty mysql-client --image=devteds/mysql-client:5.7_b1 --restart=Never -- bash -il

mysql -uappuser -pappuser123 -hbookstore-mysql bookstore
> show tables;
> show databases;
> exit

mysql -uappuser -pappuser123 -hbookstore-mysql.default.svc.cluster.local bookstore
> exit
```

Configs & Secrets

```
kubectl apply -f services/shopapi/config.yaml
kubectl get cm
kubectl describe cm/shopapi-cm

kubectl apply -f services/shopapi/secret.yaml
kubectl get secret/shopapi-sec -o yaml
```

Database schema script - use Job

```
kubectl create -f services/shopapi/job-dbc.yaml
kubectl get job -l app=shopapi-db
kubectl describe job/shopapi-job-dbc

# delete job when complete
kubectl delete job/shopapi-job-dbc
```

Deployment & Service

```
kubectl apply -f services/shopapi/deploy.yaml
kubectl get po -l app=shopapi

kubectl apply -f services/shopapi/service.yaml
kubectl get svc -l app=shopapi
```

Verify

```
kubectl port-forward svc/shopapi 3200:3000
open http://localhost:3200/api/books
```

### Service 3: Shopping UI

Deploy & Service

```
kubectl apply -f services/shopui/deploy.yaml
kubectl get po -l app=shopui

kubectl apply -f services/shopui/service.yaml
kubectl get svc -l app=shopui
```

You may verify using port forward but let's to integrated test using ingress

### Entry point (NGINX proxy)

The original Ingress controller + `route/ingress.yaml` setup has been replaced by the chart's NGINX reverse proxy. Its routing lives in `proxy.routes` in `helm/bookstore/values.yaml`. See [Deploy with Helm](#deploy-with-helm-eks--rosa--on-prem-openshift).
