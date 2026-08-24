terraform {
  cloud {
    organization = "avilashj"

    workspaces {
      name = "cortex-ai-test"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
  }
}

provider "azurerm" {
  features {}
}
