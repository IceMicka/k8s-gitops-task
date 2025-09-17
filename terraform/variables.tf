variable "repo_url" {
  type        = string
  description = "Public Git for Argo"
}

variable "mysql_root_password" {
  type        = string
  sensitive   = true
  description = "MySQL root password"
}
