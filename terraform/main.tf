terraform {
  required_version = ">= 1.0"

  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.5.0"
    }
  }

  backend "s3" {
    bucket                      = "your-terraform-state-bucket" # MUST be globally unique
    region                      = "us-east-1"                   # S3 bucket region
    endpoint                    = "s3.amazonaws.com"            # S3 endpoint URL
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
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