output "instance_name" {
  description = "Name of the compute instance"
  value       = google_compute_instance.openclaw.name
}

output "instance_zone" {
  description = "Zone where the instance is deployed"
  value       = google_compute_instance.openclaw.zone
}

output "instance_id" {
  description = "Instance ID"
  value       = google_compute_instance.openclaw.instance_id
}

output "internal_ip" {
  description = "Internal IP address of the instance"
  value       = google_compute_instance.openclaw.network_interface[0].network_ip
}

output "service_account_email" {
  description = "Service account email for the instance"
  value       = google_service_account.openclaw.email
}

output "boot_disk_name" {
  description = "Name of the boot disk"
  value       = google_compute_disk.boot.name
}

output "data_disk_name" {
  description = "Name of the data disk"
  value       = google_compute_disk.data.name
}

output "ssh_command" {
  description = "Command to SSH to the instance via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.openclaw.name} --zone=${google_compute_instance.openclaw.zone} --tunnel-through-iap --project=${var.project_id}"
}

output "ssh_with_port_forward" {
  description = "Command to SSH with port forwarding for gateway"
  value       = "gcloud compute ssh ${google_compute_instance.openclaw.name} --zone=${google_compute_instance.openclaw.zone} --tunnel-through-iap --project=${var.project_id} -- -L ${var.openclaw_gateway_port}:localhost:${var.openclaw_gateway_port} -N"
}

output "service_status_command" {
  description = "Command to check service status"
  value       = "gcloud compute ssh ${google_compute_instance.openclaw.name} --zone=${google_compute_instance.openclaw.zone} --tunnel-through-iap --project=${var.project_id} --command='sudo systemctl status openclaw-gateway'"
}

output "gateway_url" {
  description = "Local gateway URL (after port forwarding)"
  value       = "http://localhost:${var.openclaw_gateway_port}"
}

output "gateway_websocket_url" {
  description = "Local gateway WebSocket URL (after port forwarding)"
  value       = "ws://localhost:${var.openclaw_gateway_port}"
}
