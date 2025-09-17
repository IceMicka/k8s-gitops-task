## Architecture

└─ Docker (k3d) - Kubernetes 
├─ MetalLB  ─ assigns IPs for LoadBalancer services
├─ ingress-nginx ─ routes in cluster services
├─ Argo CD ─  controller (App of Apps) + Ingress
├─ Namespace: infrastructure
│ ├─ MySQL
│ ├─ Secret: mysql-root-password
│ └─ Backups: CronJob - PVC
└─ Namespace: applications
├─ Helm chart: frontend (Nginx) + backend (http-echo)
└─ Policies: LimitRange and resourceQuota

## Repo Layout

├─ README.md
├─ terraform/
│ ├─ providers.tf # helm/kubernetes/kubectl
│ ├─ namespaces.tf # argocd, infrastructure, applications
│ ├─ metallb.tf # MetalLB + IPPool
│ ├─ ingress-nginx.tf # nginx controller
│ ├─ argocd.tf # ArgoCD with ingress enabled via values
│ ├─ variables.tf # repourl, mysqlrootpassword
│ ├─ secrets.tf # mysql-root-password secret in both namespaces
│ └─ apps.tf # ArgoCD apps as kubectl manifests
├─ terraform/argocd-apps/ # “App of Apps” manifests
│ ├─ root.yaml
│ ├─ infrastructure.yaml
│ ├─ applications.yaml
│ ├─ policies.yaml
│ └─ mysql-backup.yaml
├─ applications/
│ ├─ myapp/ # Helm chart (frontend+backend+ingress)
│ │ ├─ Chart.yaml
│ │ ├─ values.yaml
│ │ └─ templates/(backend,frontend,ingress).yaml
│ └─ policies/ns-policies.yaml # LimitRange and ResourceQuota
├─ infrastructure/
│ ├─ mysql-values.yaml # reference values
│ ├─ backup-pvc.yaml # PVC 
│ └─ backup-cronjob.yaml # CronJob every 5min, keep last 10 files
└─ proxy/
└─ argocd-proxy.conf.example # WSL-friendly expose

## Cluster

k3d cluster create dev-cluster \
  --servers 1 --agents 3 \
  --k3s-arg "--disable=servicelb@server:*" # using Metallb

kubectl config use-context k3d-dev-cluster
kubectl get nodes -o wide

Confirm your Docker network and update the pool in terraform/metallb.tf

#Bootstrap-with-terraform

terraform init -upgrade
terraform apply -auto-approve \
  -var="repo_url=https://github.com/IceMicka/k8s-gitops-task.git" \
  -var="mysql_root_password=xxxxxxxxxx!"

#Apps-in-argocd

root-app → watches terraform/argocd-apps/

Child apps:

infrastructure → Bitnami MySQL chart (secret, PVC)

applications → Helm chart with frontend + backend

policies → LimitRange + ResourceQuota

mysql-backup → infrastructure/backup-*.yaml

#ArgoCD-expose

Argo CD is exposed by ingress-nginx.
# discover MetalLB IP of ingress controller
IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
sed "s/REPLACE_ME_IP/${IP}/g" proxy/argocd-proxy.conf.example > proxy/argocd-proxy.conf

docker rm -f argocd-proxy 2>/dev/null || true
docker run -d --restart unless-stopped --name argocd-proxy \
  --network k3d-dev-cluster \
  -p 18080:18080 \
  -v "$PWD/proxy/argocd-proxy.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:1.25

Add to Windows hosts run as admin, can be found /windows/system32/etc/hosts, edit with Notepad++
127.0.0.1  argocd.localtest.me

#Application-chart-frontend--backend

applications/myapp Helm chart deploys:
frontend: Nginx serving /
backend: hashicorp/http-echo serving /api

#MySQL-secret-backups

kubernetessecret.mysql-root-password in infrastructure and applications namespaces.
Set at  apply time via -var="mysql_root_password=...".
