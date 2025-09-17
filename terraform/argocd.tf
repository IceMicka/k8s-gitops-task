resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.6"

  depends_on = [
    helm_release.metallb,
    helm_release.ingress_nginx
  ]

  wait    = true
  timeout = 1200

  values = [
    yamlencode({
      server = {
        service   = { type = "ClusterIP" }
        extraArgs = ["--insecure"]
        ingress   = { enabled = false }
      }
      repoServer = {
        env = [{
          name  = "HELM_EXPERIMENTAL_OCI"
          value = "1"
        }]
      }
    })
  ]
}

resource "kubectl_manifest" "argocd_ingress" {
  depends_on = [helm_release.argocd]

  yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.localtest.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
YAML
}
