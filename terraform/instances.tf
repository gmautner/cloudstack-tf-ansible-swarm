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
  for_each = var.workers

  name             = each.key
  template         = data.cloudstack_template.main.id
  service_offering = each.value.plan
  network_id       = cloudstack_network.main.id
  zone             = data.cloudstack_zone.main.name
  keypair          = cloudstack_ssh_keypair.main.name
  expunge          = true

  tags = {
    Role = "worker"
    Name = each.key
  }
}

# Data disks for workers (varying sizes)
resource "cloudstack_disk" "worker_data" {
  for_each = var.workers

  name               = "${each.key}-data"
  attach             = true
  disk_offering      = var.disk_offering_name
  size               = each.value.data_size_gb
  virtual_machine_id = cloudstack_instance.workers[each.key].id
  zone               = data.cloudstack_zone.main.name
} 