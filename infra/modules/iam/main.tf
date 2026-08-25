# =============================================================================
# ENTRA ID USERS
# Cloud-only users simulating what would be synced from on-prem AD in production.
# In a bank: HR system → ServiceNow ITSM → AD provisioning → Entra Connect sync.
# force_password_change = true so users set their own password on first sign-in.
# =============================================================================
resource "azuread_user" "persona" {
  for_each = var.personas

  user_principal_name   = "${each.key}@${var.tenant_domain}"
  display_name          = each.value.display_name
  mail_nickname         = each.key
  password              = var.initial_password
  force_password_change = true
}

# =============================================================================
# SECURITY GROUPS
# security_enabled = true is required for Azure RBAC — Microsoft 365 groups
# cannot be used as RBAC principals. Common interview gotcha.
# =============================================================================
resource "azuread_group" "persona" {
  for_each = var.personas

  display_name     = each.value.group_name
  security_enabled = true
  mail_enabled     = false
}

resource "azuread_group_member" "persona" {
  for_each = var.personas

  group_object_id  = azuread_group.persona[each.key].object_id
  member_object_id = azuread_user.persona[each.key].object_id
}

# =============================================================================
# AZURE RBAC ROLE ASSIGNMENTS — group-based, never user-based.
# Group membership changes propagate to all role assignments automatically.
# All assignments use the group's object_id, not the user's object_id.
# =============================================================================
locals {
  dev_rg_id       = "/subscriptions/${var.subscription_id}/resourceGroups/rg-cortex-ai-dev"
  test_rg_id      = "/subscriptions/${var.subscription_id}/resourceGroups/rg-cortex-ai-test"
  subscription_id = "/subscriptions/${var.subscription_id}"

  # Flat list of {group_key, role, scope_id} — for_each key must be unique.
  # Using "group:role:scope_label" as the key.
  role_assignments = {
    # Platform admins: full control on both envs + can assign roles (UAA)
    "admin-cortex:Contributor:dev"      = { group = "admin-cortex", role = "Contributor", scope = local.dev_rg_id }
    "admin-cortex:Contributor:test"     = { group = "admin-cortex", role = "Contributor", scope = local.test_rg_id }
    "admin-cortex:UserAccessAdmin:dev"  = { group = "admin-cortex", role = "User Access Administrator", scope = local.dev_rg_id }
    "admin-cortex:UserAccessAdmin:test" = { group = "admin-cortex", role = "User Access Administrator", scope = local.test_rg_id }

    # DevOps: can deploy to both envs, cannot reassign roles
    "svc-devops:Contributor:dev"  = { group = "svc-devops", role = "Contributor", scope = local.dev_rg_id }
    "svc-devops:Contributor:test" = { group = "svc-devops", role = "Contributor", scope = local.test_rg_id }

    # Developers: full access to dev (can experiment), read-only on test
    "dev-alice:Contributor:dev" = { group = "dev-alice", role = "Contributor", scope = local.dev_rg_id }
    "dev-alice:Reader:test"     = { group = "dev-alice", role = "Reader", scope = local.test_rg_id }

    # Security: read-everything-touch-nothing across the whole subscription
    "sec-audit:SecurityReader:sub" = { group = "sec-audit", role = "Security Reader", scope = local.subscription_id }
    "sec-audit:KeyVaultReader:sub" = { group = "sec-audit", role = "Key Vault Reader", scope = local.subscription_id }
  }
}

resource "azurerm_role_assignment" "persona" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azuread_group.persona[each.value.group].object_id
}

# GitHub Actions SPN role assignments — object ID supplied from the bootstrap output.
# Roles here are minimal for now; ACR push (Phase 3) and AKS deploy (Phase 6) will
# add more. Set to empty string default in variables.tf to skip if not yet bootstrapped.
resource "azurerm_role_assignment" "gh_actions_dev_contributor" {
  count = var.gh_actions_sp_object_id != "" ? 1 : 0

  scope                = local.dev_rg_id
  role_definition_name = "Contributor"
  principal_id         = var.gh_actions_sp_object_id
}

resource "azurerm_role_assignment" "gh_actions_test_contributor" {
  count = var.gh_actions_sp_object_id != "" ? 1 : 0

  scope                = local.test_rg_id
  role_definition_name = "Contributor"
  principal_id         = var.gh_actions_sp_object_id
}

# =============================================================================
# USER-ASSIGNED MANAGED IDENTITY — for the console application
# User-assigned (not system-assigned) so the identity persists across redeploys
# and can be attached to both the local Docker container (Phase 4) and AKS pod
# (Phase 6) without changing its client ID.
# =============================================================================
resource "azurerm_user_assigned_identity" "console" {
  name                = "mid-cortex-console-${var.env}"
  location            = var.location
  resource_group_name = var.app_rg_name
  tags                = var.tags
}

# Console identity needs to read Key Vault secrets (API keys, OAuth client secrets).
# More roles are added in Phase 3 (ACR pull) and Phase 8 (Foundry/APIM access).
resource "azurerm_role_assignment" "console_kv_secrets" {
  scope                = local.dev_rg_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.console.principal_id
}

# =============================================================================
# ENTRA APP REGISTRATION — prod-access console feature
# When a user clicks "Request prod access" in the console, it creates an Entra
# app registration and returns the Application (client) ID + tenant ID.
# The requester then wires these into their workflow for client-credentials flow:
#   POST /oauth/token { client_id, client_secret, grant_type: client_credentials }
#   → Bearer token scoped to what this app registration permits
# =============================================================================
resource "azuread_application" "prod_access" {
  display_name = "cortex-ai-prod-access-${var.env}"

  # No redirect URIs — this app is for service-to-service (client credentials),
  # not user sign-in (auth code). No web/spa/implicit grant needed.
}

resource "azuread_service_principal" "prod_access" {
  client_id = azuread_application.prod_access.client_id
}
