locals {
  tags = {
    owner       = "avilashj"
    env         = "dev"
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
  env      = "dev"
  location = "uksouth"
  tags     = local.tags

  # initial_password is a sensitive TFC workspace variable — set it at:
  # app.terraform.io → cortex-ai-dev → Variables → add "initial_password" (sensitive, Terraform var)
  initial_password = var.initial_password

  # Set this after running: terraform apply in infra/bootstrap/tfc-cloud-setup
  # then: terraform output gh_actions_sp_object_id
  gh_actions_sp_object_id = var.gh_actions_sp_object_id

  acr_id = module.keyvault.acr_id
}

module "keyvault" {
  source          = "../../modules/keyvault"
  env             = "dev"
  app_rg_name     = "rg-cortex-ai-dev"
  subscription_id = "5e131d1f-220b-4c15-a3b0-4d0009629b75"
  tags            = local.tags
  vm_size         = var.management_vm_size

  # dev creates the shared management VM (WireGuard + Nexus), DNS zones, and the ACR
  create_management_vm = true
  create_dns_zones     = true
}

module "aks" {
  source        = "../../modules/aks"
  env           = "dev"
  location      = "uksouth"
  tags          = local.tags
  rg_name       = "rg-cortex-ai-dev"
  aks_subnet_id = module.network.ai_aks_subnet_id
  acr_id        = module.keyvault.acr_id

  api_server_authorized_ip_ranges = ["${module.keyvault.management_vm_public_ip}/32"]
}

# Federates the console's existing user-assigned identity (Phase 2) to a
# Kubernetes ServiceAccount via AKS's OIDC issuer - the pod authenticates as
# this identity with no secret mounted, same OIDC pattern as TFC/GH Actions.
# namespace/service_account_name here must match what charts/console's
# ServiceAccount manifest actually creates.
resource "azurerm_federated_identity_credential" "console_workload_identity" {
  name                = "console-workload-identity-dev"
  resource_group_name = "rg-cortex-ai-dev"
  parent_id           = module.iam.managed_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:dev:cortex-console"
}

# Lets the management VM's identity actually fetch and use cluster-admin
# kubeconfig (`az aks get-credentials --admin`) - the VM is the one place
# inside the API server's authorized_ip_ranges restriction, so it's where
# any interactive kubectl/helm work has to happen. Cluster Admin (not just
# Cluster User) because this is a solo-operator POC cluster, not
# multi-tenant - same admin-bypass pattern already used for branch
# protection. Wiring up Azure AD-integrated Kubernetes RBAC just to grant
# narrower in-cluster permissions is real production hardening, not done
# here.
resource "azurerm_role_assignment" "management_vm_aks_admin" {
  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = module.keyvault.management_vm_identity_principal_id
}

# Same role, for GitHub Actions' identity - services-cd.yml's deploy jobs
# need this to run `az aks get-credentials` + `helm upgrade --install` for
# real. Those jobs also run on the self-hosted runner (same reason as
# build-and-push: the API server's authorized_ip_ranges restriction means
# a GitHub-hosted runner has no path to the cluster at all).
resource "azurerm_role_assignment" "gh_actions_aks_admin" {
  count = var.gh_actions_sp_object_id != "" ? 1 : 0

  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = var.gh_actions_sp_object_id
}

# Second federated credential for the "test" namespace - without this,
# deploying the chart into a test namespace would hit the exact silent
# failure the chart's own README warns about: the ServiceAccount's subject
# wouldn't match any federated credential, and the pod would just never
# get a workload identity token, no error at deploy time.
resource "azurerm_federated_identity_credential" "console_workload_identity_test" {
  name                = "console-workload-identity-test"
  resource_group_name = "rg-cortex-ai-dev"
  parent_id           = module.iam.managed_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:test:cortex-console"
}

# Overridable without a code change: uksouth capacity for popular B/D-series SKUs
# fluctuates. If a plan fails with SkuNotAvailable, set this as a TFC workspace
# variable to a different size (e.g. Standard_A2_v2, Standard_F2s_v2) and re-run.
# Standard_D2ns_v6 confirmed available for this subscription via:
#   az vm list-skus --location uksouth --resource-type virtualMachines --all true
variable "management_vm_size" {
  type    = string
  default = "Standard_D2ns_v6"
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
# AZURE POLICY ASSIGNMENTS
# Assigned at mg-cortex-corp so they apply to our subscription automatically
# via MG inheritance. Policy definitions are built-in (no custom definition
# needed) — Azure ships hundreds; we pick the relevant ones.
# ==============================================================================

data "azurerm_management_group" "corp" {
  name = "mg-cortex-corp"
}

# Policy 1: Require tags on resource groups.
# Built-in policy id: 96670d01-0a4d-4649-9c89-2d3abc0a5025 (Require a tag on resource groups)
# Effect = Deny — new RGs without these tags will be blocked at creation time.
resource "azurerm_management_group_policy_assignment" "require_tag_owner" {
  name                 = "require-tag-owner"
  display_name         = "Require owner tag on resource groups"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  management_group_id  = data.azurerm_management_group.corp.id

  parameters = jsonencode({
    tagName = { value = "owner" }
  })
}

resource "azurerm_management_group_policy_assignment" "require_tag_env" {
  name                 = "require-tag-env"
  display_name         = "Require env tag on resource groups"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  management_group_id  = data.azurerm_management_group.corp.id

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
  management_group_id  = data.azurerm_management_group.corp.id
}
