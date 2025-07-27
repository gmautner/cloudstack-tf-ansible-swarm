# Create isolated network
resource "cloudstack_network" "main" {
  name               = "swarm-network"
  cidr               = "10.1.0.0/24"
  network_offering   = data.cloudstack_network_offering.main.id
  zone               = data.cloudstack_zone.main.name
  display_text       = "Docker Swarm Network"
}

# Acquire public IP
resource "cloudstack_ipaddress" "main" {
  network_id = cloudstack_network.main.id
  zone       = data.cloudstack_zone.main.name
}

# Create SSH keypair
resource "cloudstack_ssh_keypair" "main" {
  name       = "swarm-keypair"
  public_key = var.ssh_public_key
}

# Firewall rules for HTTP/HTTPS traffic
resource "cloudstack_firewall" "web" {
  ip_address_id = cloudstack_ipaddress.main.id

  rule {
    cidr_list = ["0.0.0.0/0"]
    protocol    = "tcp"
    ports       = ["80", "443"]
  }
}

# Firewall rules for SSH access (ports 22001-22100)
resource "cloudstack_firewall" "ssh" {
  ip_address_id = cloudstack_ipaddress.main.id

  rule {
    cidr_list   = var.allowed_ssh_cidr_blocks
    protocol    = "tcp"
    ports       = ["22001-22100"]
  }
} 