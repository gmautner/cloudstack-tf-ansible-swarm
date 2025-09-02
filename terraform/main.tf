terraform {
  backend "local" {
    # The state path is configured dynamically in the Makefile
    # using the -backend-config flag for terraform init.
    # This allows for separate state files per environment (e.g., dev, prod)
    # to be stored under the environments/ directory.
  }

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
  # api_url will be sourced from CLOUDSTACK_API_URL environment variable
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