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
        name = cloudstack_instance.managers[i].name
        port = 22001 + i
        private_ip = cloudstack_instance.managers[i].ip_address
      }
    ]
    workers = [
      for i in range(length(var.workers)) : {
        name = cloudstack_instance.workers[i].name
        port = 22004 + i
        private_ip = cloudstack_instance.workers[i].ip_address
        role = var.workers[i].name
      }
    ]
    domain_suffix = var.domain_suffix
  })
  filename = "${path.module}/inventory.ini"
} 