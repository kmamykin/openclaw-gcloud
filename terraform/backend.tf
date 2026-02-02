# Terraform state backend configuration
# The bucket will be created by scripts/setup.sh

terraform {
  backend "gcs" {
    bucket = "REPLACE_WITH_PROJECT_ID-terraform-state"
    prefix = "openclaw/compute"
  }
}
