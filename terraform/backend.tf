terraform {
  backend "local" {
    # The state path is configured dynamically in the Makefile
    # using the -backend-config flag for terraform init.
    # This allows for separate state files per environment (e.g., dev, prod)
    # to be stored under the environments/ directory.
  }
}
