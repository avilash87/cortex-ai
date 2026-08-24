terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
  }
}

# Local state deliberately - hub networking must exist before any spoke can peer to it.
provider "azurerm" {
  features {}
}
