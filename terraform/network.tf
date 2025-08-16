# Create isolated network
resource "cloudstack_network" "main" {
  name             = "${var.cluster_name}-network"
  cidr             = "192.168.1.0/24"
  network_offering = data.cloudstack_network_offering.main.id
  zone             = data.cloudstack_zone.main.name
  display_text     = "Docker Swarm Network for ${var.cluster_name}"
}

# Main public IP for SSH access and management
resource "cloudstack_ipaddress" "main" {
  network_id = cloudstack_network.main.id
  zone       = data.cloudstack_zone.main.name
}

# Create public IP addresses for each configured service
resource "cloudstack_ipaddress" "public_ips" {
  for_each = var.public_ips
  
  network_id = cloudstack_network.main.id
  zone       = data.cloudstack_zone.main.name
}

# Create SSH keypair
resource "cloudstack_ssh_keypair" "main" {
  name = "${var.cluster_name}-${var.env}"
}

# Create a flattened list of all ports across all public IPs for dependency tracking
locals {
  all_ports = flatten([
    for ip_name, ip_config in var.public_ips : [
      for port in ip_config.ports : {
        ip_name      = ip_name
        public_port  = port.public
        private_port = port.private
        protocol     = port.protocol
        allowed_cidrs = port.allowed_cidrs
      }
    ]
  ])
}

# Dynamic firewall rules for each port configuration
resource "cloudstack_firewall" "ports" {
  for_each = {
    for idx, port in local.all_ports : "${port.ip_name}-${port.public_port}" => port
  }

  depends_on = [
    cloudstack_loadbalancer_rule.ports,
  ]

  ip_address_id = cloudstack_ipaddress.public_ips[each.value.ip_name].id

  rule {
    cidr_list = each.value.allowed_cidrs
    protocol  = each.value.protocol == "tcp-proxy" ? "tcp" : each.value.protocol
    ports     = [tostring(each.value.public_port)]
  }
}

# Firewall rules for SSH access (ports 22001-22100) - using the main public IP
resource "cloudstack_firewall" "ssh" {
  depends_on = [
    cloudstack_port_forward.manager_ssh,
    cloudstack_port_forward.worker_ssh
  ]

  ip_address_id = cloudstack_ipaddress.main.id

  rule {
    cidr_list = var.allowed_ssh_cidr_blocks
    protocol  = "tcp"
    ports     = ["22001-22100"]
  }
}