# App-of-Apps
resource "kubectl_manifest" "root_app" {
  depends_on = [helm_release.argocd]
  yaml_body  = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${var.repo_url}
    path: terraform/argocd-apps
    targetRevision: HEAD
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}

# Bitnami MySQL Helm chart
# repo manifests (backup, CronJob)
resource "kubectl_manifest" "infra_app" {
  depends_on = [kubectl_manifest.root_app]
  yaml_body  = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  sources:
  - repoURL: https://charts.bitnami.com/bitnami
    chart: mysql
    targetRevision: 11.1.21
    helm:
      values: |
        auth:
          existingSecret: mysql-root-password
          database: demo
          createDatabase: true
        primary:
          persistence:
            enabled: true
            size: 1Gi
  - repoURL: ${var.repo_url}
    targetRevision: HEAD
    path: infrastructure
  destination:
    server: https://kubernetes.default.svc
    namespace: infrastructure
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}

# Helm chart in the repo
# namespace policies limits
resource "kubectl_manifest" "apps_app" {
  depends_on = [kubectl_manifest.root_app]
  yaml_body  = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: applications
  namespace: argocd
spec:
  project: default
  sources:
  - repoURL: ${var.repo_url}
    targetRevision: HEAD
    path: applications/myapp
  - repoURL: ${var.repo_url}
    targetRevision: HEAD
    path: applications/policies
  destination:
    server: https://kubernetes.default.svc
    namespace: applications
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}
