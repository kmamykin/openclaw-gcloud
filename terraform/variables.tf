variable "project_id" {
  description = "GCP Project ID"
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "GCP zone for compute instance"
  type        = string
  default     = "us-east1-b"
}

variable "instance_name" {
  description = "Name of the compute instance"
  type        = string
  default     = "openclaw-gateway"
}

variable "machine_type" {
  description = "Machine type for compute instance"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = can(regex("^(e2-micro|e2-small|e2-medium|n1-standard-1)$", var.machine_type))
    error_message = "Machine type must be a valid GCE machine type. Use e2-micro for free tier."
  }
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 10

  validation {
    condition     = var.boot_disk_size_gb >= 10 && var.boot_disk_size_gb <= 100
    error_message = "Boot disk size must be between 10 and 100 GB."
  }
}

variable "data_disk_size_gb" {
  description = "Data disk size in GB for /home mount"
  type        = number
  default     = 20

  validation {
    condition     = var.data_disk_size_gb >= 10 && var.data_disk_size_gb <= 100
    error_message = "Data disk size must be between 10 and 100 GB."
  }
}

variable "openclaw_version" {
  description = "OpenClaw npm package version to install"
  type        = string
  default     = "2026.1.30"

  validation {
    condition     = can(regex("^\\d{4}\\.\\d{1,2}\\.\\d{1,2}$", var.openclaw_version))
    error_message = "OpenClaw version must be in format YYYY.M.D or YYYY.MM.DD."
  }
}

variable "gog_version" {
  description = "gog CLI version to install"
  type        = string
  default     = "0.9.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.gog_version))
    error_message = "gog version must be in semver format (e.g., 0.9.0)."
  }
}

variable "openclaw_gateway_token" {
  description = "Authentication token for OpenClaw gateway"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.openclaw_gateway_token) >= 32
    error_message = "Gateway token must be at least 32 characters. Generate with: openssl rand -hex 32"
  }
}

variable "openclaw_gateway_port" {
  description = "Port for OpenClaw gateway to listen on"
  type        = number
  default     = 18789

  validation {
    condition     = var.openclaw_gateway_port >= 1024 && var.openclaw_gateway_port <= 65535
    error_message = "Gateway port must be between 1024 and 65535."
  }
}

variable "openclaw_gateway_bind" {
  description = "Bind mode for OpenClaw gateway (loopback, lan, all)"
  type        = string
  default     = "loopback"

  validation {
    condition     = can(regex("^(loopback|lan|all)$", var.openclaw_gateway_bind))
    error_message = "Gateway bind must be one of: loopback, lan, all."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    managed_by  = "terraform"
    application = "openclaw"
  }
}

variable "enable_os_login" {
  description = "Enable OS Login for SSH access"
  type        = bool
  default     = true
}
