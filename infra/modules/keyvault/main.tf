data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "sandbox" {
  name                = var.sandbox_spoke_vnet_name
  resource_group_name = var.sandbox_spoke_rg_name
}

data "azurerm_subnet" "sandbox_general" {
  name                 = var.sandbox_general_subnet_name
  virtual_network_name = data.azurerm_virtual_network.sandbox.name
  resource_group_name  = var.sandbox_spoke_rg_name
}

data "azurerm_subnet" "sandbox_private_endpoints" {
  name                 = var.sandbox_private_endpoints_subnet_name
  virtual_network_name = data.azurerm_virtual_network.sandbox.name
  resource_group_name  = var.sandbox_spoke_rg_name
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "tls_private_key" "management_vm" {
  count     = var.create_management_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# =============================================================================
# KEY VAULT — public access disabled, required by Phase 1 Azure Policy
# =============================================================================
resource "azurerm_key_vault" "this" {
  name                          = "kv-cortex-${var.env}-${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.app_rg_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  public_network_access_enabled = false
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = ["Get", "List", "Set", "Delete"]
  }
}

resource "azurerm_key_vault_secret" "vm_ssh_private_key" {
  count        = var.create_management_vm ? 1 : 0
  name         = "management-vm-ssh-private-key"
  value        = tls_private_key.management_vm[0].private_key_pem
  key_vault_id = azurerm_key_vault.this.id
  content_type = "OpenSSH private key"
}

# =============================================================================
# STORAGE ACCOUNT
# =============================================================================
resource "azurerm_storage_account" "this" {
  name                          = "stcortex${var.env}${random_string.suffix.result}"
  resource_group_name           = var.app_rg_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  public_network_access_enabled = false
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  tags                          = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# =============================================================================
# ACR — shared registry; both envs use the same one created by dev
# =============================================================================
resource "azurerm_container_registry" "this" {
  count                         = var.env == "dev" ? 1 : 0
  name                          = "acrcortex${random_string.suffix.result}"
  resource_group_name           = var.app_rg_name
  location                      = var.location
  sku                           = var.acr_sku
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
}

data "azurerm_container_registry" "shared" {
  count               = var.env == "dev" ? 0 : 1
  name                = "acrcortex"
  resource_group_name = "rg-cortex-ai-dev"
}

locals {
  acr_id           = var.env == "dev" ? azurerm_container_registry.this[0].id : data.azurerm_container_registry.shared[0].id
  acr_login_server = var.env == "dev" ? azurerm_container_registry.this[0].login_server : data.azurerm_container_registry.shared[0].login_server
}

# =============================================================================
# MANAGEMENT VM — created once (dev only); hosts WireGuard + Nexus
# =============================================================================
resource "azurerm_public_ip" "management" {
  count               = var.create_management_vm ? 1 : 0
  name                = "pip-cortex-management-${var.env}"
  location            = var.location
  resource_group_name = var.management_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "management" {
  count               = var.create_management_vm ? 1 : 0
  name                = "nic-cortex-management-${var.env}"
  location            = var.location
  resource_group_name = var.management_rg_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.sandbox_general.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.management[0].id
  }
}

resource "azurerm_linux_virtual_machine" "management" {
  count               = var.create_management_vm ? 1 : 0
  name                = "vm-cortex-management-${var.env}"
  location            = var.location
  resource_group_name = var.management_rg_name
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.management[0].id,
  ]
  disable_password_authentication = true
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.management_vm[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# =============================================================================
# PRIVATE DNS ZONES — created once by dev, looked up by test
# Production design: these live in the Connectivity hub subscription.
# POC simplification: created in rg-cortex-management-dev, shared by both envs.
# =============================================================================
resource "azurerm_private_dns_zone" "key_vault" {
  count               = var.create_dns_zones ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.management_rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "blob" {
  count               = var.create_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.management_rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.create_dns_zones ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = var.management_rg_name
  tags                = var.tags
}

data "azurerm_private_dns_zone" "key_vault" {
  count               = var.create_dns_zones ? 0 : 1
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.existing_dns_zones_rg_name
}

data "azurerm_private_dns_zone" "blob" {
  count               = var.create_dns_zones ? 0 : 1
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.existing_dns_zones_rg_name
}

data "azurerm_private_dns_zone" "acr_zone" {
  count               = var.create_dns_zones ? 0 : 1
  name                = "privatelink.azurecr.io"
  resource_group_name = var.existing_dns_zones_rg_name
}

locals {
  kv_zone_id   = var.create_dns_zones ? azurerm_private_dns_zone.key_vault[0].id : data.azurerm_private_dns_zone.key_vault[0].id
  blob_zone_id = var.create_dns_zones ? azurerm_private_dns_zone.blob[0].id : data.azurerm_private_dns_zone.blob[0].id
  acr_zone_id  = var.create_dns_zones ? azurerm_private_dns_zone.acr[0].id : data.azurerm_private_dns_zone.acr_zone[0].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = var.create_dns_zones ? 1 : 0
  name                  = "link-kv-sandbox"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = data.azurerm_virtual_network.sandbox.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.create_dns_zones ? 1 : 0
  name                  = "link-blob-sandbox"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = data.azurerm_virtual_network.sandbox.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.create_dns_zones ? 1 : 0
  name                  = "link-acr-sandbox"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = data.azurerm_virtual_network.sandbox.id
  registration_enabled  = false
}

# =============================================================================
# PRIVATE ENDPOINTS — per-env (each env has its own KV/storage endpoints)
# =============================================================================
resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-cortex-${var.env}"
  location            = var.location
  resource_group_name = var.app_rg_name
  subnet_id           = data.azurerm_subnet.sandbox_private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-cortex-${var.env}"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.kv_zone_id]
  }
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-blob-cortex-${var.env}"
  location            = var.location
  resource_group_name = var.app_rg_name
  subnet_id           = data.azurerm_subnet.sandbox_private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob-cortex-${var.env}"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.blob_zone_id]
  }
}

resource "azurerm_private_endpoint" "acr" {
  count               = var.env == "dev" ? 1 : 0
  name                = "pe-acr-cortex-${var.env}"
  location            = var.location
  resource_group_name = var.app_rg_name
  subnet_id           = data.azurerm_subnet.sandbox_private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-acr-cortex-${var.env}"
    private_connection_resource_id = local.acr_id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [local.acr_zone_id]
  }
}
