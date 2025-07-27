terraform {
  required_version = ">= 1.0"
  
  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.5.0"
    }
  }
}

# Configure the CloudStack Provider
provider "cloudstack" {
  api_url = "https://painel-cloud.locaweb.com.br/client/api"
}

# Data sources for CloudStack resources
data "cloudstack_zone" "main" {
  name = "ZP01"
}

data "cloudstack_zone" "backup" {
  name = "ZP02"
}

data "cloudstack_network_offering" "main" {
  name = var.network_offering_name
}

data "cloudstack_template" "main" {
  template_filter = "featured"
  name            = var.template_name
  zone_id         = data.cloudstack_zone.main.id
}

data "cloudstack_disk_offering" "data" {
  name = var.disk_offering_name
} 