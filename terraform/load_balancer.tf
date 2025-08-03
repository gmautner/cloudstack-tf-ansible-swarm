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

# Port forwarding rules for SSH access to managers (22001-22003)
# Using the main public IP for SSH access (separate from service IPs)
resource "cloudstack_port_forward" "manager_ssh" {
  count = var.manager_count

  ip_address_id = cloudstack_ipaddress.main.id

  forward {
    protocol           = "tcp"
    public_port        = 22001 + count.index
    private_port       = 22
    virtual_machine_id = cloudstack_instance.managers[count.index].id
  }
}

# Port forwarding rules for SSH access to workers (starting at 22004)
# Using the main public IP for SSH access (separate from service IPs)
resource "cloudstack_port_forward" "worker_ssh" {
  for_each = var.workers

  ip_address_id = cloudstack_ipaddress.main.id

  forward {
    protocol           = "tcp"
    public_port        = 22004 + index(keys(var.workers), each.key)
    private_port       = 22
    virtual_machine_id = cloudstack_instance.workers[each.key].id
  }
}