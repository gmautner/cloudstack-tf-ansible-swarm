terraform {
  backend "s3" {
    bucket                      = "gmautner-cluster-2"
    region                      = "us-east-2"
    endpoint                    = "s3.amazonaws.com"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
