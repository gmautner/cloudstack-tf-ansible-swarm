# Dynamic load balancer rules for each port configuration
# Using all workers as members because Docker Swarm creates a VIP
# that routes traffic to the appropriate services regardless of destination
resource "cloudstack_loadbalancer_rule" "ports" {
  for_each = {
    for idx, port in local.all_ports : "${port.ip_name}-${port.public_port}" => port
  }

  name          = "${each.value.ip_name}-${each.value.public_port}-lb"
  description   = "Load balancer rule for ${each.value.ip_name} port ${each.value.public_port} (${each.value.protocol})"
  ip_address_id = cloudstack_ipaddress.public_ips[each.value.ip_name].id
  algorithm     = "roundrobin"
  network_id    = cloudstack_network.main.id
  protocol      = each.value.protocol
  public_port   = each.value.public_port
  private_port  = each.value.private_port
  member_ids    = [for worker in cloudstack_instance.workers : worker.id]
}

# Create a map of all SSH port forwarding rules for managers and workers
locals {
  manager_forwards = {
    for i in range(var.manager_count) :
    cloudstack_instance.managers[i].id => {
      public_port = 22001 + i
    }
  }

  worker_forwards = {
    for i, name in keys(var.workers) :
    cloudstack_instance.workers[name].id => {
      public_port = 22004 + i
    }
  }

  all_ssh_forwards = merge(local.manager_forwards, local.worker_forwards)
}

# Port forwarding rules for SSH access to all managers and workers
# Using the main public IP for SSH access (separate from service IPs)
resource "cloudstack_port_forward" "ssh" {
  ip_address_id = cloudstack_ipaddress.main.id

  dynamic "forward" {
    for_each = local.all_ssh_forwards
    content {
      protocol           = "tcp"
      public_port        = forward.value.public_port
      private_port       = 22
      virtual_machine_id = forward.key
    }
  }
}