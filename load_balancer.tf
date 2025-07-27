# Load balancer rules for HTTP and HTTPS traffic to manager-1
resource "cloudstack_loadbalancer_rule" "http" {
  name           = "http-lb"
  description    = "Load balancer rule for HTTP traffic"
  ip_address_id  = cloudstack_ipaddress.main.id
  algorithm      = "roundrobin"
  network_id     = cloudstack_network.main.id
  public_port    = 80
  private_port   = 80
  member_ids     = [cloudstack_instance.managers[0].id]
}

resource "cloudstack_loadbalancer_rule" "https" {
  name           = "https-lb"
  description    = "Load balancer rule for HTTPS traffic"
  ip_address_id  = cloudstack_ipaddress.main.id
  algorithm      = "roundrobin"
  network_id     = cloudstack_network.main.id
  public_port    = 443
  private_port   = 443
  member_ids     = [cloudstack_instance.managers[0].id]
}

# Port forwarding rules for SSH access to managers (22001-22003)
resource "cloudstack_port_forward" "manager_ssh" {
  count = 3

  ip_address_id = cloudstack_ipaddress.main.id

  forward {
    protocol           = "tcp"
    public_port        = 22001 + count.index
    private_port       = 22
    virtual_machine_id = cloudstack_instance.managers[count.index].id
  }
}

# Port forwarding rules for SSH access to workers (starting at 22004)
resource "cloudstack_port_forward" "worker_ssh" {
  count = length(var.workers)

  ip_address_id = cloudstack_ipaddress.main.id

  forward {
    protocol           = "tcp"
    public_port        = 22004 + count.index
    private_port       = 22
    virtual_machine_id = cloudstack_instance.workers[count.index].id
  }
} 