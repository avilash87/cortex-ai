variable "tfc_organization" {
  description = "HCP Terraform organization name"
  type        = string
  default     = "avilashj"
}

variable "tfc_project" {
  description = "HCP Terraform project name that owns the workspaces"
  type        = string
  default     = "Default Project"
}

variable "github_owner" {
  description = "GitHub username or org that owns the repo"
  type        = string
  default     = "avilash87"
}

variable "github_repo_name" {
  description = "Repository name (without owner prefix)"
  type        = string
  default     = "cortex-ai"
}

variable "create_github_repo" {
  description = "Set true to create the repo. Set false if it already exists on GitHub."
  type        = bool
  default     = false
}

# GitHub PAT with scopes: repo, admin:repo_hook
# Pass via: export TF_VAR_github_token="ghp_xxxx"  (never hardcode)
# Rotating the token = update the env var + terraform apply; no TFC UI needed.
variable "github_token" {
  description = "GitHub Personal Access Token — manages TFC VCS OAuth client and GitHub provider"
  type        = string
  sensitive   = true
}

variable "envs" {
  description = "One entry per environment: TFC workspace name + apply gate"
  type = map(object({
    workspace_name = string
    auto_apply     = bool # true = merge to master deploys immediately; false = requires manual Confirm & Apply in TFC UI
  }))
  default = {
    dev = {
      workspace_name = "cortex-ai-dev"
      auto_apply     = true # dev auto-deploys on merge — fast feedback loop
    }
    test = {
      workspace_name = "cortex-ai-test"
      auto_apply     = false # test requires a human to review the plan and click Confirm & Apply
    }
  }
}
