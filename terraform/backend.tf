terraform {
  backend "s3" {
    bucket                      = "giba-swarm-terraform-states"
    region                      = "us-east-2"
  }
}
