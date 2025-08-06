# Random variables for snapshot schedules
resource "random_integer" "snapshot_minute_hourly" {
  min = 0
  max = 59
}

resource "random_integer" "snapshot_hour_daily" {
  min = 0
  max = 23
}

resource "random_integer" "snapshot_weekday" {
  min = 1
  max = 7
}

resource "random_integer" "snapshot_day_monthly" {
  min = 1
  max = 28
}

# Calculate snapshot schedules
locals {
  # Calculate snapshot schedules
  snapshot_minute_hourly = random_integer.snapshot_minute_hourly.result
  snapshot_minute_daily  = (random_integer.snapshot_minute_hourly.result + 30) % 60
  snapshot_hour_daily    = random_integer.snapshot_hour_daily.result
  snapshot_hour_weekly   = (random_integer.snapshot_hour_daily.result + 8) % 24
  snapshot_hour_monthly  = (random_integer.snapshot_hour_daily.result + 16) % 24
  snapshot_weekday       = random_integer.snapshot_weekday.result
  snapshot_day_monthly   = random_integer.snapshot_day_monthly.result
  
  # Schedule strings
  schedule_hourly  = format("%02d", local.snapshot_minute_hourly)
  schedule_daily   = format("%02d:%02d", local.snapshot_minute_daily, local.snapshot_hour_daily)
  schedule_weekly  = format("%02d:%02d:%02d", local.snapshot_minute_daily, local.snapshot_hour_weekly, local.snapshot_weekday)
  schedule_monthly = format("%02d:%02d:%02d", local.snapshot_minute_daily, local.snapshot_hour_monthly, local.snapshot_day_monthly)
  
  # Zone IDs for snapshots
  zone_ids = "${data.cloudstack_zone.main.id},${data.cloudstack_zone.backup.id}"
}

# Create snapshot policies for worker data disks using CloudMonkey (cmk)
resource "null_resource" "worker_snapshot_policies" {
  for_each = var.workers
  
  depends_on = [
    cloudstack_disk.worker_data
  ]

  # Initialize CloudMonkey with credentials
  provisioner "local-exec" {
    command = "cmk set url $CLOUDSTACK_API_URL && cmk set apikey $CLOUDSTACK_API_KEY && cmk set secretkey $CLOUDSTACK_SECRET_KEY"
  }

  # Hourly snapshots
  provisioner "local-exec" {
    command = "cmk create snapshotpolicy intervaltype=HOURLY schedule=${local.schedule_hourly} timezone=Etc/UTC volumeid=${cloudstack_disk.worker_data[each.key].id} maxsnaps=3 zoneids=${local.zone_ids} tags[0].key=cluster_id tags[0].value=${local.cluster_id}"
  }

  # Daily snapshots
  provisioner "local-exec" {
    command = "cmk create snapshotpolicy intervaltype=DAILY schedule=${local.schedule_daily} timezone=Etc/UTC volumeid=${cloudstack_disk.worker_data[each.key].id} maxsnaps=2 zoneids=${local.zone_ids} tags[0].key=cluster_id tags[0].value=${local.cluster_id}"
  }

  # Weekly snapshots
  provisioner "local-exec" {
    command = "cmk create snapshotpolicy intervaltype=WEEKLY schedule=${local.schedule_weekly} timezone=Etc/UTC volumeid=${cloudstack_disk.worker_data[each.key].id} maxsnaps=2 zoneids=${local.zone_ids} tags[0].key=cluster_id tags[0].value=${local.cluster_id}"
  }

  # Monthly snapshots
  provisioner "local-exec" {
    command = "cmk create snapshotpolicy intervaltype=MONTHLY schedule=${local.schedule_monthly} timezone=Etc/UTC volumeid=${cloudstack_disk.worker_data[each.key].id} maxsnaps=2 zoneids=${local.zone_ids} tags[0].key=cluster_id tags[0].value=${local.cluster_id}"
  }
}