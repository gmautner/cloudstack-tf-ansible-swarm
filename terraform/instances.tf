# Manager instances
resource "cloudstack_instance" "managers" {
  count = 3

  name             = "manager-${count.index + 1}"
  template         = data.cloudstack_template.main.id
  service_offering = "medium"
  network_id       = cloudstack_network.main.id
  zone             = data.cloudstack_zone.main.name
  keypair          = cloudstack_ssh_keypair.main.name
  expunge          = true

  tags = {
    Role = "manager"
    Name = "manager-${count.index + 1}"
  }
}

# Data disks for managers (50GB each)
resource "cloudstack_disk" "manager_data" {
  count = 3

  name               = "manager-${count.index + 1}-data"
  attach             = true
  disk_offering      = var.disk_offering_name
  size               = 50
  virtual_machine_id = cloudstack_instance.managers[count.index].id
  zone               = data.cloudstack_zone.main.name
}

# Worker instances
resource "cloudstack_instance" "workers" {
  count = length(var.workers)

  name             = var.workers[count.index].name
  template         = data.cloudstack_template.main.id
  service_offering = var.workers[count.index].plan
  network_id       = cloudstack_network.main.id
  zone             = data.cloudstack_zone.main.name
  keypair          = cloudstack_ssh_keypair.main.name
  expunge          = true

  tags = {
    Role = "worker"
    Name = var.workers[count.index].name
  }
}

# Data disks for workers (varying sizes)
resource "cloudstack_disk" "worker_data" {
  count = length(var.workers)

  name               = "${var.workers[count.index].name}-data"
  attach             = true
  disk_offering      = var.disk_offering_name
  size               = var.workers[count.index].data_size_gb
  virtual_machine_id = cloudstack_instance.workers[count.index].id
  zone               = data.cloudstack_zone.main.name
} 