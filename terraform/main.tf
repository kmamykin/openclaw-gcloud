# Data source for latest Debian 12 image
data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# Service account for the compute instance
resource "google_service_account" "openclaw" {
  account_id   = "${var.instance_name}-sa"
  display_name = "OpenClaw Gateway Service Account"
  description  = "Minimal-permission service account for OpenClaw gateway VM"
}

# IAM roles for service account
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# Boot disk for the instance
resource "google_compute_disk" "boot" {
  name  = "${var.instance_name}-boot"
  type  = "pd-standard"
  zone  = var.zone
  image = data.google_compute_image.debian.self_link
  size  = var.boot_disk_size_gb

  labels = var.labels

  lifecycle {
    prevent_destroy = true
  }
}

# Data disk for /home directory
resource "google_compute_disk" "data" {
  name = "${var.instance_name}-data"
  type = "pd-standard"
  zone = var.zone
  size = var.data_disk_size_gb

  labels = var.labels

  lifecycle {
    prevent_destroy = true
  }
}

# Firewall rule to allow SSH from IAP
resource "google_compute_firewall" "iap_ssh" {
  name    = "allow-iap-ssh-${var.instance_name}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP IP range

  target_tags = ["iap-ssh"]

  description = "Allow SSH access from Identity-Aware Proxy"
}

# Compute instance
resource "google_compute_instance" "openclaw" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["iap-ssh"]

  boot_disk {
    source      = google_compute_disk.boot.id
    auto_delete = false
  }

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "data"
  }

  network_interface {
    network = "default"
    # No external IP - access via IAP only
  }

  service_account {
    email  = google_service_account.openclaw.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = var.enable_os_login ? "TRUE" : "FALSE"
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup-script.sh.tpl", {
    openclaw_version = var.openclaw_version
    gog_version      = var.gog_version
    gateway_token    = var.openclaw_gateway_token
    gateway_port     = var.openclaw_gateway_port
    gateway_bind     = var.openclaw_gateway_bind
    data_device_name = "data"
  })

  labels = var.labels

  allow_stopping_for_update = true

  lifecycle {
    # Ignore changes to startup script - use update-version.sh instead
    ignore_changes = [metadata_startup_script]
  }
}
