terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
  }
}

# Local state deliberately - a tenant-root-scope bootstrap, same shape as tfc-oidc.
provider "azurerm" {
  features {}
}
