# Terraform state backend configuration
# The bucket will be created by scripts/setup.sh

terraform {
  backend "gcs" {
    bucket = "openclaw-kmamyk-terraform-state"
    prefix = "openclaw/compute"
  }
}
