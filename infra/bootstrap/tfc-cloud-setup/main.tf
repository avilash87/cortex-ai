data "azurerm_subscription" "current" {}

# One app registration per env keeps blast radius separate (dev creds can't touch test).
resource "azuread_application" "tfc" {
  for_each     = var.envs
  display_name = "cortex-ai-tfc-${each.key}"
}

resource "azuread_service_principal" "tfc" {
  for_each  = azuread_application.tfc
  client_id = each.value.client_id
}

# HCP Terraform requests a separately-scoped token per run phase, so each phase needs its own credential.
resource "azuread_application_federated_identity_credential" "plan" {
  for_each       = var.envs
  application_id = azuread_application.tfc[each.key].id
  display_name   = "tfc-${each.key}-plan"
  description    = "HCP Terraform plan phase for workspace ${each.value.workspace_name}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://app.terraform.io"
  subject        = "organization:${var.tfc_organization}:project:${var.tfc_project}:workspace:${each.value.workspace_name}:run_phase:plan"
}

resource "azuread_application_federated_identity_credential" "apply" {
  for_each       = var.envs
  application_id = azuread_application.tfc[each.key].id
  display_name   = "tfc-${each.key}-apply"
  description    = "HCP Terraform apply phase for workspace ${each.value.workspace_name}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://app.terraform.io"
  subject        = "organization:${var.tfc_organization}:project:${var.tfc_project}:workspace:${each.value.workspace_name}:run_phase:apply"
}

# Scoped to subscription so the management-group bootstrap (which runs second and creates
# the RGs) does not need to know TFC SPN object IDs in advance.
resource "azurerm_role_assignment" "tfc_contributor" {
  for_each             = var.envs
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.tfc[each.key].object_id
}

# ============================================================================
# GITHUB REPOSITORY
# Looks up (or creates) the repo and manages settings. Branch protection on a
# private repo requires GitHub Pro — enforced instead via required GH Actions
# status checks in Phase 5 (free on all plans).
# ============================================================================
data "github_repository" "cortex_ai" {
  count = var.create_github_repo ? 0 : 1
  name  = var.github_repo_name
}

resource "github_repository" "cortex_ai" {
  count       = var.create_github_repo ? 1 : 0
  name        = var.github_repo_name
  description = "Cortex AI POC — Azure platform learning project"
  visibility  = "private"
  auto_init   = true
}

locals {
  repo_name = var.create_github_repo ? github_repository.cortex_ai[0].name : data.github_repository.cortex_ai[0].name
}

# ============================================================================
# TFC WORKSPACES + VARIABLES
# VCS connection (GitHub → TFC) is wired manually once via TFC UI:
#   Settings → VCS Providers → GitHub → Authorize → copy OAuth Token ID
#   then re-apply with -var="tfc_vcs_oauth_token_id=ot-xxxx"
# Workspaces are API-driven until the VCS token is provided.
# ============================================================================
resource "tfe_workspace" "env" {
  for_each     = var.envs
  name         = each.value.workspace_name
  organization = var.tfc_organization

  working_directory = "infra/envs/${each.key}"
  auto_apply        = false
  terraform_version = "~> 1.15"
  queue_all_runs    = false

  dynamic "vcs_repo" {
    for_each = var.tfc_vcs_oauth_token_id != "" ? [1] : []
    content {
      identifier     = "${var.github_owner}/${local.repo_name}"
      oauth_token_id = var.tfc_vcs_oauth_token_id
      branch         = "master"
    }
  }
}

locals {
  # Workspace env vars required for HCP Terraform dynamic credentials (OIDC to Azure).
  workspace_vars = {
    for env_key, env_val in var.envs : env_key => {
      TFC_AZURE_PROVIDER_AUTH = "true"
      TFC_AZURE_RUN_CLIENT_ID = azuread_application.tfc[env_key].client_id
      ARM_TENANT_ID           = data.azurerm_subscription.current.tenant_id
      ARM_SUBSCRIPTION_ID     = data.azurerm_subscription.current.subscription_id
    }
  }
}

resource "tfe_variable" "workspace" {
  for_each = merge([
    for env_key, vars in local.workspace_vars : {
      for var_key, var_val in vars : "${env_key}:${var_key}" => {
        workspace_id = tfe_workspace.env[env_key].id
        key          = var_key
        value        = var_val
      }
    }
  ]...)

  workspace_id = each.value.workspace_id
  key          = each.value.key
  value        = each.value.value
  category     = "env"
  sensitive    = false
}
