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
  filter {
    name  = "name"
    value = "ZP01"
  }
}

data "cloudstack_zone" "backup" {
  filter {
    name  = "name"
    value = "ZP02"
  }
}

data "cloudstack_network_offering" "main" {
  filter {
    name  = "name"
    value = var.network_offering_name
  }
}

data "cloudstack_template" "main" {
  template_filter = "featured"
  filter {
    name  = "name"
    value = var.template_name
  }
} 