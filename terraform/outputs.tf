# Output the main public IP address (dedicated for SSH access)
output "main_public_ip" {
  description = "Main public IP address used for SSH access and management"
  value       = cloudstack_ipaddress.main.ip_address
}

# Output all service-specific public IP addresses
output "service_public_ips" {
  description = "Map of public IP addresses for each service"
  value = {
    for ip_name, ip_resource in cloudstack_ipaddress.public_ips : ip_name => ip_resource.ip_address
  }
}



# Output calculated manager service offering
output "manager_service_offering" {
  description = "Service offering assigned to managers based on worker pool size"
  value       = local.manager_service_offering
}

# Output worker count for reference
output "worker_count" {
  description = "Total number of workers in the cluster"
  value       = local.worker_count
}

# Output cluster name
output "cluster_name" {
  description = "Name of the cluster"
  value       = var.cluster_name
}

# Output cluster ID
output "cluster_id" {
  description = "Unique cluster identifier"
  value       = local.cluster_id
}

# Output snapshot schedules for reference
output "snapshot_schedules" {
  description = "Calculated snapshot schedules for worker data disks"
  value = {
    hourly  = local.schedule_hourly
    daily   = local.schedule_daily
    weekly  = local.schedule_weekly
    monthly = local.schedule_monthly
  }
}

output "private_key" {
  description = "Private key for SSH access to the instances"
  value       = cloudstack_ssh_keypair.main.private_key
  sensitive   = true
}

locals {
  domain_suffix = "${var.env}.${var.cluster_name}.${var.base_domain}"
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    cluster_name                = var.cluster_name
    public_ip                   = cloudstack_ipaddress.main.ip_address
    domain_suffix               = local.domain_suffix
    automatic_reboot            = var.automatic_reboot
    automatic_reboot_time_utc   = var.automatic_reboot_time_utc
    managers = [
      for i in range(var.manager_count) : {
        name       = cloudstack_instance.managers[i].name
        port       = local.all_ssh_forwards[cloudstack_instance.managers[i].id].public_port
        private_ip = cloudstack_instance.managers[i].ip_address
      }
    ]
    workers = [
      for worker_name in keys(var.workers) : {
        name       = cloudstack_instance.workers[worker_name].name
        port       = local.all_ssh_forwards[cloudstack_instance.workers[worker_name].id].public_port
        private_ip = cloudstack_instance.workers[worker_name].ip_address
        labels     = var.workers[worker_name].labels
      }
    ]
  })
  filename = "${path.module}/../environments/${var.env}/inventory.yml"
}