terraform {
  backend "s3" {
    bucket                      = "gmautner-cluster-2"
    region                      = "us-east-2"
  }
}
