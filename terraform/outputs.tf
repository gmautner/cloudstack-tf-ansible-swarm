# Output the public IP address
output "public_ip" {
  description = "Public IP address for the infrastructure"
  value       = cloudstack_ipaddress.main.ip_address
}

# Output domain suffix for use in Ansible
output "domain_suffix" {
  description = "Domain suffix for WordPress and Traefik access"
  value       = var.domain_suffix
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

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    public_ip = cloudstack_ipaddress.main.ip_address
    managers = [
      for i in range(var.manager_count) : {
        name       = cloudstack_instance.managers[i].name
        port       = tolist(cloudstack_port_forward.manager_ssh[i].forward)[0].public_port
        private_ip = cloudstack_instance.managers[i].ip_address
      }
    ]
    workers = [
      for worker_name in keys(var.workers) : {
        name       = cloudstack_instance.workers[worker_name].name
        port       = tolist(cloudstack_port_forward.worker_ssh[worker_name].forward)[0].public_port
        private_ip = cloudstack_instance.workers[worker_name].ip_address
        role       = worker_name
      }
    ]
    domain_suffix = var.domain_suffix
  })
  filename = "${path.module}/../ansible/inventory.ini"
}