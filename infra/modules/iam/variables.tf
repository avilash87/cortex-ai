variable "env" {
  description = "Environment name (dev or test) — used in resource names and UPN suffixes"
  type        = string
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "subscription_id" {
  description = "Subscription GUID — used as RBAC scope for subscription-wide roles"
  type        = string
  default     = "5e131d1f-220b-4c15-a3b0-4d0009629b75"
}

variable "app_rg_name" {
  description = "Resource group where the managed identity is created"
  type        = string
  default     = "rg-cortex-ai-dev"
}

# Temporary password issued to all test users. Users must change it on first sign-in.
# Pass via TFC workspace variable (sensitive) — never hardcode.
# In production: password is set by the IdP provisioning workflow (e.g. ServiceNow → AD);
# Entra cloud-only users like these would have passwords managed via SSPR or a PAM tool.
variable "initial_password" {
  description = "Initial password for all Entra ID test personas (force_password_change=true)"
  type        = string
  sensitive   = true
}

# GitHub Actions SPN object ID — created in the bootstrap alongside TFC OIDC.
# RBAC grants for CI/CD are managed here so they follow the same per-env pattern
# as all other role assignments. The SPN itself (app reg + federated creds) lives
# in the bootstrap because it must exist before the TFC workspace can run Phase 2.
variable "gh_actions_sp_object_id" {
  description = "Object ID of the GitHub Actions service principal (from tfc-cloud-setup outputs)"
  type        = string
  default     = "" # set once Phase 2 bootstrap apply has run
}

variable "personas" {
  description = "Test user personas — cloud-only Entra ID users simulating an on-prem AD sync"
  type = map(object({
    display_name = string
    group_name   = string
  }))
  default = {
    "admin-cortex" = {
      display_name = "Cortex Platform Admin"
      group_name   = "grp-cortex-platform-admins"
    }
    "svc-devops" = {
      display_name = "DevOps Service Account"
      group_name   = "grp-cortex-devops"
    }
    "dev-alice" = {
      display_name = "Alice Developer"
      group_name   = "grp-cortex-developers"
    }
    "sec-audit" = {
      display_name = "Security Auditor"
      group_name   = "grp-cortex-security-audit"
    }
  }
}
