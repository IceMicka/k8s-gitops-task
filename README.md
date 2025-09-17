# K8s — Argo CD “App of Apps”, MySQL with Backups, Frontend/Backend Helm Chart

- Cluster: k3d (1 control-plane, 3 workers), MetalLB for LoadBalancer IPs, ingress-nginx as ingress
- GitOps: Argo CD installed by Terraform + “App of Apps” that watches this repo
- Secrets: Terraform creates Kubernetes Secrets they won't be stored on Git
- Database: Bitnami MySQL with init schema and 5-minute CronJob backups (retain last 10)
- Application: Helm chart with frontend (nginx) + backend (http-echo) + ingress
- Access: Permanent local access via a small WSL nginx proxy

---

## Architecture

Docker -> Kubernetes (1 server, 3 agents)
|-- MetalLB: provides external IPs for LoadBalancer Services
|-- ingress-nginx: HTTP/HTTPS ingress
|-- Argo CD (installed via Terraform)
    |-- Root app that syncs this repo:
        |-- infrastructure (MySQL chart + init + backup CronJob + PVC)
        |-- applications (custom Helm chart: frontend + backend + ingress)
        |-- policies (resource quotas and limit ranges)
|-- Namespaces:
    |-- argocd
    |-- infrastructure
    |-- applications

---

## Repository layout

├─ README.md
├─ terraform/
│ ├─ providers.tf # helm/kubernetes/kubectl
│ ├─ namespaces.tf # argocd, infrastructure, applications
│ ├─ metallb.tf # MetalLB + IPAddressPool
│ ├─ ingress-nginx.tf # ingress-nginx chart
│ ├─ argocd.tf # Argo CD chart + argocd Ingress
│ ├─ apps.tf # Argo CD Applications
│ ├─ secrets.tf # mysql-root-password secrets
│ ├─ variables.tf # repo_url, mysql_root_password
│ └─ argocd-apps/ # YAMLs by Argo CD
│ ├─ root.yaml
│ ├─ infrastructure.yaml
│ ├─ applications.yaml
│ ├─ policies.yaml
│ └─ mysql-backup.yaml
├─ applications/
│ └─ myapp/ # custom Helm chart
│ ├─ Chart.yaml
│ ├─ values.yaml
│ └─ templates/
│ ├─ backend.yaml
│ ├─ frontend.yaml
│ └─ ingress.yaml
├─ infrastructure/
│ ├─ mysql-values.yaml
│ ├─ mysql-initdb-configmap.yaml
│ ├─ backup-pvc.yaml
│ └─ backup-cronjob.yaml
└─ proxy/
└─ argocd-proxy.conf.example

---

## Prerequisites

- Windows 10/11 with WSL2 (Ubuntu 22.04)
- Docker Desktop with WSL integration enabled
- kubectl, k3d, Terraform (>= 1.7), Helm (v3)

---

## Create the local multi-node cluster (k3d)

# Create 1 server + 3 agents; disable K3s servicelb (we use MetalLB)
k3d cluster create dev-cluster \
  --servers 1 --agents 3 \
  --api-port 6550 \
  --k3s-arg "--disable=servicelb@server:*"

kubectl config use-context k3d-dev-cluster
kubectl get nodes -o wide

# Terraform installs MetalLB, ingress-nginx, Argo CD, creates namespaces, applies the Argo CD Applications (App of Apps).
cd terraform
terraform init -upgrade
terraform apply -auto-approve \
  -var="repo_url=https://github.com/IceMicka/k8s-gitops-task.git" \
  -var="mysql_root_password=***"  # passwd is a variable needs to set with the apply

Verify the workload is running as expected
kubectl get pods -A
kubectl -n argocd get deploy,svc,ing
kubectl -n ingress-nginx get svc,pods -o wide

# Create nginx container inside WSL that forwards to the MetalLB IP
Get the MetalLB IP of the ingress controller service
export INGRESS_IP=$(kubectl -n ingress-nginx \
  get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

Proxy config that points to INGRESS_IP
sed "s/REPLACE_ME_IP/${INGRESS_IP}/g" \
  ../proxy/argocd-proxy.conf.example > ../proxy/argocd-proxy.conf

Start the proxy container
docker rm -f argocd-proxy 2>/dev/null || true
docker run -d --restart unless-stopped --name argocd-proxy \
  --network k3d-dev-cluster \
  -p 18080:18080 \
  -v "$PWD/proxy/argocd-proxy.conf:/etc/nginx/conf.d/default.conf:ro" \
  nginx:1.25

If on windows add to C:\Windows\System32\drivers\etc\hosts but run as Admin
127.0.0.1  argocd.localtest.me myapp.localtest.me

Test from browser
http://argocd.localtest.me:18080/
http://myapp.localtest.me:18080/

# Database and backups
infrastructure/mysql-initdb-configmap.yaml
Backups: infrastructure/backup-cronjob.yaml runs every 5 minutes, writing dumps to the PVC defined in infrastructure/backup-pvc.yaml. Retention is 10 latest backups.

Basic checks
kubectl -n infrastructure get statefulset,svc,pvc,cm,cronjob,job | sed -n '1,120p'
Should like similar to this
ice@LAPTOP-66P41854:~$ kubectl -n infrastructure get statefulset,svc,pvc,cm,cronjob,job | sed -n '1,120p'
NAME                     READY   AGE
statefulset.apps/mysql   1/1     10h

NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/mysql   ClusterIP   10.43.174.137   <none>        3306/TCP   10h

NAME                                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-mysql-0       Bound    pvc-d547c465-8fab-4d11-85ba-9cbe7e215ce0   1Gi        RWO            local-path     <unset>                 11h
persistentvolumeclaim/mysql-backup-pvc   Bound    pvc-7b8c62a8-62f5-4362-8fe5-8f9158762417   2Gi        RWO            local-path     <unset>                 10h

NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      31h
configmap/mysql-initdb       1      10h

NAME                         SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/mysql-backup   */5 * * * *   <none>     False     0        4m29s           10h

NAME                              STATUS     COMPLETIONS   DURATION   AGE
job.batch/mysql-backup-29301530   Complete   1/1           6s         49m
job.batch/mysql-backup-29301535   Complete   1/1           5s         44m
job.batch/mysql-backup-29301540   Complete   1/1           7s         39m
job.batch/mysql-backup-29301545   Complete   1/1           4s         34m
job.batch/mysql-backup-29301550   Complete   1/1           4s         29m
job.batch/mysql-backup-29301555   Complete   1/1           4s         24m
job.batch/mysql-backup-29301560   Complete   1/1           4s         19m
job.batch/mysql-backup-29301565   Complete   1/1           4s         14m
job.batch/mysql-backup-29301570   Complete   1/1           5s         9m29s
job.batch/mysql-backup-29301575   Complete   1/1           5s         4m29s

# Checklist
Check the nodes
kubectl get nodes -o wide

ArgoCD apps synced and Healthy
kubectl -n argocd get applications

Check the ingress
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide

Check app objects
kubectl -n applications get deploy,svc,ingress

Check backups are running
kubectl -n infrastructure get cronjob
kubectl -n infrastructure get jobs --sort-by=.metadata.creationTimestamp | tail -n 3
