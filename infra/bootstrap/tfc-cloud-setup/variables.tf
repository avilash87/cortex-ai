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

# GitHub PAT with scopes: repo, admin:repo_hook, read:org
# Used for: GitHub provider (repo/branch-protection), TFC OAuth client (VCS connection).
# Generate at https://github.com/settings/tokens → classic → check repo + admin:repo_hook
variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

# Get from TFC UI after one-time GitHub OAuth: Settings → VCS Providers → GitHub → Authorise.
# Leave empty to keep workspaces API-driven (GitHub Actions triggers TFC via API instead).
variable "tfc_vcs_oauth_token_id" {
  description = "TFC OAuth token ID for GitHub VCS connection (optional — set after manual UI step)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "envs" {
  description = "One entry per environment: TFC workspace name"
  type = map(object({
    workspace_name = string
  }))
  default = {
    dev = {
      workspace_name = "cortex-ai-dev"
    }
    test = {
      workspace_name = "cortex-ai-test"
    }
  }
}
