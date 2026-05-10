variable "cluster_name" {
  description = "Name of the kind cluster to create. Used as both the kind cluster name and the BNK cluster_id."
  type        = string
  default     = "bnk"
}

variable "ssh_user" {
  description = "Optional SSH user from the bare-metal credential template. Combined with ssh_host to derive DOCKER_HOST=ssh://user@host. Leave empty to use the local Docker socket."
  type        = string
  default     = ""
}

variable "ssh_host" {
  description = "Optional SSH host from the bare-metal credential template. Combined with ssh_user to derive DOCKER_HOST=ssh://user@host. Leave empty to use the local Docker socket."
  type        = string
  default     = ""
}

variable "docker_host" {
  description = "Optional explicit DOCKER_HOST override (e.g. ssh://user@host or tcp://host:2375). When empty, ssh_user/ssh_host are used if both are set; otherwise the provider falls back to /var/run/docker.sock on the bnk-forge worker container."
  type        = string
  default     = ""
}

variable "kind_node_image" {
  description = "Optional kind node image override (e.g. kindest/node:v1.31.0). When empty, the provider's default for the installed kind version is used."
  type        = string
  default     = ""
}

variable "far_auth_key" {
  description = "F5 Artifacts Registry auth (extracted f5-far-auth-key.tgz contents). Auto-injected by bnk-forge from the project secret of the same name. When non-empty, cluster-create runs `helm registry login repo.f5.com` so downstream modules' helm_release OCI chart pulls succeed without per-module auth plumbing."
  type        = string
  sensitive   = true
  default     = ""
}
