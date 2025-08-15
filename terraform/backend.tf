terraform {
  backend "s3" {
    bucket                      = "your-terraform-state-bucket" # MUST be globally unique
    region                      = "us-east-1"                   # S3 bucket region
    endpoint                    = "s3.amazonaws.com"            # S3 endpoint URL
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
