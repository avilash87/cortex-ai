variable "location" {
  type    = string
  default = "uksouth"
}

variable "subscription_id" {
  type    = string
  default = "5e131d1f-220b-4c15-a3b0-4d0009629b75"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "app_rg_name" {
  type    = string
  default = "rg-cortex-ai-dev"
}

variable "management_rg_name" {
  type    = string
  default = "rg-cortex-management-dev"
}

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
  description = "Small VM size for the management/Nexus/WireGuard lab host"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "acr_sku" {
  description = "Premium is required for Azure Container Registry private endpoints"
  type        = string
  default     = "Premium"
}
