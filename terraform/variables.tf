variable "network_offering_name" {
  description = "Name of the network offering to use for the isolated network"
  type        = string
  default     = "Default Guest Network"
}

variable "template_name" {
  description = "Name of the template to use for instances"
  type        = string
  default     = "^Ubuntu.*24.*$"
}

variable "disk_offering_name" {
  description = "Name of the disk offering to use for data disks"
  type        = string
  default     = "data.disk.general"
}

variable "ssh_public_key" {
  description = "SSH public key to add to instances"
  type        = string
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to access SSH ports (22001-22100)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "workers" {
  description = "Map of worker nodes to create"
  type = map(object({
    plan         = string
    data_size_gb = number
    labels       = optional(map(string), {})
  }))
}

variable "manager_count" {
  description = "Número de managers do Docker Swarm (permitido: 1 ou 3, default: 3)"
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 3], var.manager_count)
    error_message = "O número de managers deve ser 1 ou 3."
  }
}