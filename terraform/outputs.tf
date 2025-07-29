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

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    public_ip = cloudstack_ipaddress.main.ip_address
    managers = [
      for i in range(3) : {
        name       = cloudstack_instance.managers[i].name
        port       = 22001 + i
        private_ip = cloudstack_instance.managers[i].ip_address
      }
    ]
    workers = [
      for idx, worker_name in keys(var.workers) : {
        name       = cloudstack_instance.workers[worker_name].name
        port       = 22004 + idx
        private_ip = cloudstack_instance.workers[worker_name].ip_address
        role       = worker_name
      }
    ]
    domain_suffix = var.domain_suffix
  })
  filename = "${path.module}/../ansible/inventory.ini"
}