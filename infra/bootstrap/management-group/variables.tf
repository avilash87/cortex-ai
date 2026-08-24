variable "subscription_id" {
  description = "Subscription GUID to place under the management group"
  type        = string
  default     = "5e131d1f-220b-4c15-a3b0-4d0009629b75"
}

variable "location" {
  description = "Azure region for all landing-zone resource groups"
  type        = string
  default     = "uksouth"
}

variable "tags_base" {
  description = "Tags applied to every resource group; env tag is merged per-RG"
  type        = map(string)
  default = {
    owner       = "avilashj"
    cost-centre = "cortex-ai-poc"
  }
}
