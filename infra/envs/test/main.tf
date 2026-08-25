locals {
  tags = {
    owner       = "avilashj"
    env         = "test"
    cost-centre = "cortex-ai-poc"
  }
}

module "network" {
  source   = "../../modules/network"
  location = "uksouth"
  tags     = local.tags
}

module "iam" {
  source   = "../../modules/iam"
  env      = "test"
  location = "uksouth"
  tags     = local.tags

  initial_password        = var.initial_password
  gh_actions_sp_object_id = var.gh_actions_sp_object_id
}

module "keyvault" {
  source          = "../../modules/keyvault"
  env             = "test"
  app_rg_name     = "rg-cortex-ai-test"
  subscription_id = "5e131d1f-220b-4c15-a3b0-4d0009629b75"
  tags            = local.tags

  # test uses the VM, DNS zones, and ACR already created by the dev workspace
  create_management_vm       = false
  create_dns_zones           = false
  existing_dns_zones_rg_name = "rg-cortex-management-dev"
}

variable "initial_password" {
  description = "Initial password for test Entra ID users — set as a sensitive TFC workspace variable"
  type        = string
  sensitive   = true
}

variable "gh_actions_sp_object_id" {
  description = "GitHub Actions SPN object ID from tfc-cloud-setup bootstrap output"
  type        = string
  default     = ""
}

# ==============================================================================
# AZURE POLICY ASSIGNMENTS — same policies as dev, applied to test scope
# ==============================================================================

data "azurerm_management_group" "corp" {
  name = "mg-cortex-corp"
}

resource "azurerm_management_group_policy_assignment" "require_tag_owner" {
  name                 = "require-tag-owner-test"
  display_name         = "Require owner tag on resource groups (test)"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  management_group_id  = data.azurerm_management_group.corp.id

  parameters = jsonencode({
    tagName = { value = "owner" }
  })
}
