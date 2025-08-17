# Random string for cluster suffix
resource "random_string" "cluster_suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Calculate manager service offering based on worker pool size
# 1-10 workers: medium, 11-100 workers: large, >100 workers: xlarge
locals {
  worker_count = length(var.workers)
  manager_service_offering = local.worker_count <= 10 ? "medium" : (
    local.worker_count <= 100 ? "large" : "xlarge"
  )
  cluster_id = "${var.cluster_name}-${random_string.cluster_suffix.result}"
}

# Manager instances
resource "cloudstack_instance" "managers" {
  count = var.manager_count

  name             = "manager-${count.index + 1}"
  template         = data.cloudstack_template.main.id
  service_offering = local.manager_service_offering
  network_id       = cloudstack_network.main.id
  zone             = data.cloudstack_zone.main.name
  keypair          = cloudstack_ssh_keypair.main.name
  expunge          = true

  tags = {
    role         = "manager"
    name         = "manager-${count.index + 1}"
    cluster_name = var.cluster_name
    cluster_id   = local.cluster_id
    env          = var.env
  }
}

# Data disks for managers (50GB each)
resource "cloudstack_disk" "manager_data" {
  count = var.manager_count

  name               = "manager-${count.index + 1}-data"
  attach             = true
  disk_offering      = var.disk_offering_name
  size               = 50
  virtual_machine_id = cloudstack_instance.managers[count.index].id
  zone               = data.cloudstack_zone.main.name

  tags = cloudstack_instance.managers[count.index].tags
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
    role         = "worker"
    name         = each.key
    cluster_name = var.cluster_name
    cluster_id   = local.cluster_id
    env          = var.env
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

  tags = cloudstack_instance.workers[each.key].tags

  lifecycle {
    ignore_changes = [name]
  }
}