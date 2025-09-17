resource "kubernetes_secret" "mysql_root_infra" {
  metadata {
    name      = "mysql-root-password"
    namespace = "infrastructure"
  }
  data = {
    password = base64encode(var.mysql_root_password)
  }
  type = "Opaque"
}

resource "kubernetes_secret" "mysql_root_apps" {
  metadata {
    name      = "mysql-root-password"
    namespace = "applications"
  }
  data = {
    password = base64encode(var.mysql_root_password)
  }
  type = "Opaque"
}
