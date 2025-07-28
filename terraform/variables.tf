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

variable "domain_suffix" {
  description = "Domain suffix for WordPress and Traefik access"
  type        = string
}

variable "workers" {
  description = "List of worker nodes to create"
  type = list(object({
    name         = string
    plan         = string
    data_size_gb = number
  }))
}