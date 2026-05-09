variable "cluster_name" {
  description = "Name of the existing kind cluster to register."
  type        = string
  default     = "bnk"
}

variable "ssh_user" {
  description = "Optional SSH user from a bare-metal credential template; combined with ssh_host into DOCKER_HOST=ssh://user@host. Empty = use local Docker socket."
  type        = string
  default     = ""
}

variable "ssh_host" {
  description = "Optional SSH host from a bare-metal credential template; combined with ssh_user into DOCKER_HOST=ssh://user@host. Empty = use local Docker socket."
  type        = string
  default     = ""
}

variable "docker_host" {
  description = "Optional explicit DOCKER_HOST override (e.g. ssh://user@host or tcp://host:2375). Takes precedence over ssh_user/ssh_host."
  type        = string
  default     = ""
}
