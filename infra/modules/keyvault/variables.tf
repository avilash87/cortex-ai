variable "env" {
  description = "Environment name used in resource names (dev, test)"
  type        = string
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "subscription_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "app_rg_name" {
  description = "Landing-zone RG where Key Vault, storage, ACR and their private endpoints are created"
  type        = string
}

variable "management_rg_name" {
  description = "Shared management RG used for DNS zones and management VM"
  type        = string
  default     = "rg-cortex-management-dev"
}

# Sandbox spoke is shared across environments in this single-subscription POC.
variable "sandbox_spoke_rg_name" {
  type    = string
  default = "rg-cortex-spoke-sandbox-dev"
}

variable "sandbox_spoke_vnet_name" {
  type    = string
  default = "vnet-spoke-sandbox-cortex-dev"
}

variable "sandbox_general_subnet_name" {
  type    = string
  default = "snet-general"
}

variable "sandbox_private_endpoints_subnet_name" {
  type    = string
  default = "snet-private-endpoints"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "acr_sku" {
  description = "Premium is required for private endpoints on ACR"
  type        = string
  default     = "Premium"
}

# Set true only for the environment that creates the shared management VM.
# Only one VM is needed: it hosts WireGuard and Nexus for all environments.
variable "create_management_vm" {
  type    = bool
  default = false
}

# Set true for the first environment (dev) that creates the three private DNS zones.
# Test env sets this to false and looks up the zones already created by dev.
variable "create_dns_zones" {
  type    = bool
  default = true
}

# Used when create_dns_zones = false to locate zones created by another env call.
variable "existing_dns_zones_rg_name" {
  type    = string
  default = "rg-cortex-management-dev"
}
