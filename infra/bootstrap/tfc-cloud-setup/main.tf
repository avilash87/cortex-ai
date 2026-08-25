data "azurerm_subscription" "current" {}

# Microsoft Graph service principal — looked up to grant app role assignments (admin consent).
data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

# One app registration per env keeps blast radius separate (dev creds can't touch test).
resource "azuread_application" "tfc" {
  for_each     = var.envs
  display_name = "cortex-ai-tfc-${each.key}"

  # Declare the Graph API permissions the SPN will need for Phase 2 (IAM module).
  # Declaration alone is not enough — azuread_app_role_assignment below grants + consents them.
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "741f803b-c850-494e-b5df-cde7c675a1ca" # User.ReadWrite.All
      type = "Role"
    }
    resource_access {
      id   = "62a82d76-70ea-41e2-9197-370581804d09" # Group.ReadWrite.All
      type = "Role"
    }
    resource_access {
      id   = "dbaae8cf-10b5-4b86-a4a1-f871c94c6695" # GroupMember.ReadWrite.All
      type = "Role"
    }
    resource_access {
      id   = "1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9" # Application.ReadWrite.All
      type = "Role"
    }
  }
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

# =============================================================================
# GITHUB ACTIONS OIDC — Phase 2 addition
# Same pattern as TFC OIDC: no stored secret, trust is the federated credential.
# Issuer is GitHub's OIDC provider (not app.terraform.io).
# Three credentials: one for PR checks (any branch), one for CD per env.
# RBAC grants for this SPN live in infra/modules/iam/ (per-env, via TFC).
# =============================================================================
resource "azuread_application" "gh_actions" {
  display_name = "cortex-ai-gh-actions"
}

resource "azuread_service_principal" "gh_actions" {
  client_id = azuread_application.gh_actions.client_id
}

resource "azuread_application_federated_identity_credential" "gh_pr" {
  application_id = azuread_application.gh_actions.id
  display_name   = "gh-pr-checks"
  description    = "GitHub Actions CI — runs on any PR to validate infra before merge"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_owner}/${var.github_repo_name}:pull_request"
}

resource "azuread_application_federated_identity_credential" "gh_env" {
  for_each       = var.envs
  application_id = azuread_application.gh_actions.id
  display_name   = "gh-env-${each.key}"
  description    = "GitHub Actions CD — runs when deploying to the ${each.key} environment"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # environment: scoped to a named GitHub Environment — phase 5 creates dev + test environments
  subject = "repo:${var.github_owner}/${var.github_repo_name}:environment:${each.key}"
}

# Scoped to subscription so the management-group bootstrap (which runs second and creates
# the RGs) does not need to know TFC SPN object IDs in advance.
resource "azurerm_role_assignment" "tfc_contributor" {
  for_each             = var.envs
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.tfc[each.key].object_id
}

# Reader at mg-cortex-corp lets Terraform data sources query the management group
# (e.g. data.azurerm_management_group for policy assignments in infra/envs/*).
resource "azurerm_role_assignment" "tfc_mg_reader" {
  for_each             = var.envs
  scope                = "/providers/Microsoft.Management/managementGroups/mg-cortex-corp"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.tfc[each.key].object_id
}

# Policy assignment writes are explicitly excluded from Contributor — Azure treats
# governance/authorization actions separately from resource management. This role
# grants exactly Microsoft.Authorization/policyAssignments/* at the MG scope.
resource "azurerm_role_assignment" "tfc_mg_policy_contributor" {
  for_each             = var.envs
  scope                = "/providers/Microsoft.Management/managementGroups/mg-cortex-corp"
  role_definition_name = "Resource Policy Contributor"
  principal_id         = azuread_service_principal.tfc[each.key].object_id
}

# User Access Administrator lets the TFC SPN write role assignments (azurerm_role_assignment).
# Contributor explicitly excludes Microsoft.Authorization/*/Write — this fills that gap.
resource "azurerm_role_assignment" "tfc_user_access_admin" {
  for_each             = var.envs
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.tfc[each.key].object_id
}

# Grant + admin-consent the Microsoft Graph application permissions declared in
# required_resource_access above. Without this step the declaration is display-only.
# One azuread_app_role_assignment = one granted + consented permission.
locals {
  graph_app_roles = {
    "User.ReadWrite.All"        = "741f803b-c850-494e-b5df-cde7c675a1ca"
    "Group.ReadWrite.All"       = "62a82d76-70ea-41e2-9197-370581804d09"
    "GroupMember.ReadWrite.All" = "dbaae8cf-10b5-4b86-a4a1-f871c94c6695"
    "Application.ReadWrite.All" = "1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9"
  }
  # Cartesian product: {env_key}:{permission_name}
  tfc_graph_grants = {
    for pair in setproduct(keys(var.envs), keys(local.graph_app_roles)) :
    "${pair[0]}:${pair[1]}" => {
      env_key     = pair[0]
      app_role_id = local.graph_app_roles[pair[1]]
    }
  }
}

resource "azuread_app_role_assignment" "tfc_graph" {
  for_each            = local.tfc_graph_grants
  app_role_id         = each.value.app_role_id
  principal_object_id = azuread_service_principal.tfc[each.value.env_key].object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# ============================================================================
# GITHUB REPOSITORY + BRANCH RULESET
# Repo is public — rulesets work on free GitHub accounts for public repos.
# Ruleset enforces: no direct pushes to master, PR required, status checks
# must pass (GH Actions fmt/validate/scan + TFC speculative plan).
# ============================================================================
data "github_repository" "cortex_ai" {
  count = var.create_github_repo ? 0 : 1
  name  = var.github_repo_name
}

resource "github_repository" "cortex_ai" {
  count       = var.create_github_repo ? 1 : 0
  name        = var.github_repo_name
  description = "Cortex AI POC — Azure platform learning project"
  visibility  = "public"
  auto_init   = true
}

locals {
  repo_name = var.create_github_repo ? github_repository.cortex_ai[0].name : data.github_repository.cortex_ai[0].name
}

# # Ruleset: only PR merges allowed on master; listed status checks must be green.
# # Lab-vs-production: in production a CODEOWNERS file + 2 reviewers minimum
# # and a separate "prod" environment with a required-reviewers gate would be added.
# resource "github_repository_ruleset" "master" {
#   name        = "master-branch-protection"
#   repository  = local.repo_name
#   target      = "branch"
#   enforcement = "active"

#   conditions {
#     ref_name {
#       include = ["refs/heads/master"]
#       exclude = []
#     }
#   }

#   rules {
#     # Block direct pushes and force-pushes to master
#     deletion         = true
#     non_fast_forward = true

#     # Require a PR with at least 1 approval
#     pull_request {
#       required_approving_review_count = 1
#       dismiss_stale_reviews_on_push   = true
#       require_code_owner_review       = false
#       require_last_push_approval      = false
#     }

#     # Context strings must match each job's *display* name exactly (the `name:`
#     # field in infra-pr.yml), not the job id — GitHub Actions reports check runs
#     # under the display name. Matrix jobs get "(<matrix value>)" auto-appended.
#     # 15368 = GitHub Actions app integration ID (constant across all repos).
#     required_status_checks {
#       strict_required_status_checks_policy = true

#       required_check {
#         context        = "Terraform format"
#         integration_id = 15368
#       }
#       required_check {
#         context        = "Terraform validate (dev)"
#         integration_id = 15368
#       }
#       required_check {
#         context        = "Terraform validate (test)"
#         integration_id = 15368
#       }
#       required_check {
#         context        = "Trivy IaC scan"
#         integration_id = 15368
#       }
#       required_check {
#         context        = "OPA / Conftest policy check"
#         integration_id = 15368
#       }
#     }
#   }

#   # Repo admin (you, working standalone) can merge without waiting for a
#   # separate approver or all checks — useful for solo work. Team/production
#   # setups would remove this bypass so no single person can self-approve.
#   bypass_actors {
#     actor_id    = 5 # built-in "Admin" repository role
#     actor_type  = "RepositoryRole"
#     bypass_mode = "always"
#   }
# }

# ============================================================================
# TFC VCS OAUTH CLIENT — GitHub connection via PAT, fully Terraform-managed.
# PAT replaces the manual UI OAuth flow that expired. Terraform owns the token
# so rotation = update the variable + re-apply, no TFC UI required.
# Required PAT scopes: repo, admin:repo_hook
# ============================================================================
resource "tfe_oauth_client" "github" {
  organization     = var.tfc_organization
  api_url          = "https://api.github.com"
  http_url         = "https://github.com"
  oauth_token      = var.github_token
  service_provider = "github"
}

# ============================================================================
# TFC WORKSPACES + VARIABLES
# ============================================================================
resource "tfe_workspace" "env" {
  for_each     = var.envs
  name         = each.value.workspace_name
  organization = var.tfc_organization

  working_directory = "infra/envs/${each.key}"
  # dev: auto_apply=true, deploys immediately on merge (PR approval is the gate).
  # test: auto_apply=false, requires a human to click Confirm & Apply in TFC UI
  # after reviewing the plan — the promotion gate from dev to test.
  auto_apply        = each.value.auto_apply
  terraform_version = "~> 1.15"
  queue_all_runs    = false

  vcs_repo {
    identifier     = "${var.github_owner}/${local.repo_name}"
    oauth_token_id = tfe_oauth_client.github.oauth_token_id
    branch         = "master"
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
