resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.11.2"

  set {
    name  = "controller.publishService.enabled"
    value = "true"
  }

  wait    = true
  timeout = 600
}
