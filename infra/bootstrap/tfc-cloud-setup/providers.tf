terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.57"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# Local state deliberately - this bootstrap must exist before TFC can auth to Azure at all.
provider "azuread" {}

provider "azurerm" {
  features {}
}

# Authenticates using the token stored by `terraform login`.
provider "tfe" {
  organization = var.tfc_organization
}

# Same PAT is used for both the GitHub repo management and the TFC VCS OAuth client.
provider "github" {
  token = var.github_token
}
