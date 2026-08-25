locals {
  tags = {
    owner       = "avilashj"
    env         = "dev"
    cost-centre = "cortex-ai-poc"
  }
  # Hardcoded — the MG ARM path never changes once created. Avoids needing
  # MG Reader permissions for the TFC service principal beyond subscription scope.
  corp_mg_id = "/providers/Microsoft.Management/managementGroups/mg-cortex-corp"
}

module "network" {
  source   = "../../modules/network"
  location = "uksouth"
  tags     = local.tags
}

# =============================================================================
# AZURE POLICY ASSIGNMENTS
# Assigned at mg-cortex-corp so they apply to our subscription automatically
# via MG inheritance. Policy definitions are built-in (no custom definition
# needed) — Azure ships hundreds; we pick the relevant ones.
# =============================================================================

# Policy 1: Require tags on resource groups.
# Built-in policy id: 96670d01-0a4d-4649-9c89-2d3abc0a5025 (Require a tag on resource groups)
# Effect = Deny — new RGs without these tags will be blocked at creation time.
resource "azurerm_management_group_policy_assignment" "require_tag_owner" {
  name                 = "require-tag-owner"
  display_name         = "Require owner tag on resource groups"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  management_group_id  = local.corp_mg_id

  parameters = jsonencode({
    tagName = { value = "owner" }
  })
}

resource "azurerm_management_group_policy_assignment" "require_tag_env" {
  name                 = "require-tag-env"
  display_name         = "Require env tag on resource groups"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  management_group_id  = local.corp_mg_id

  parameters = jsonencode({
    tagName = { value = "env" }
  })
}

# Policy 2: Deny public network access on Key Vault.
# Built-in policy id: 405c5871-3e91-4644-8a63-58e19d68ff5b
# Effect = Deny — any Key Vault created in this MG scope must have public network access disabled.
resource "azurerm_management_group_policy_assignment" "deny_keyvault_public" {
  name                 = "deny-kv-public-access"
  display_name         = "Deny public network access on Key Vault"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/405c5871-3e91-4644-8a63-58e19d68ff5b"
  management_group_id  = local.corp_mg_id
}
