resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  version          = "0.13.12"

  wait    = true
  timeout = 600
}

resource "kubectl_manifest" "metallb_ip_pool" {
  depends_on = [helm_release.metallb]
  yaml_body  = <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-address-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.19.255.200-172.19.255.250
YAML
}

resource "kubectl_manifest" "metallb_l2_adv" {
  depends_on = [helm_release.metallb, kubectl_manifest.metallb_ip_pool]
  yaml_body  = <<YAML
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-adv
  namespace: metallb-system
spec: {}
YAML
}
