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
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-cortex-${random_string.suffix.result}"
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

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
    ]
  }
}

resource "azurerm_key_vault_secret" "vm_ssh_private_key" {
  name         = "management-vm-ssh-private-key"
  value        = tls_private_key.management_vm.private_key_pem
  key_vault_id = azurerm_key_vault.this.id
  content_type = "OpenSSH private key"

  depends_on = [azurerm_key_vault.this]
}

resource "azurerm_storage_account" "this" {
  name                          = "stcortex${random_string.suffix.result}"
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

resource "azurerm_container_registry" "this" {
  name                          = "acrcortex${random_string.suffix.result}"
  resource_group_name           = var.app_rg_name
  location                      = var.location
  sku                           = var.acr_sku
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_network_interface" "management" {
  name                = "nic-cortex-management-dev"
  location            = var.location
  resource_group_name = var.management_rg_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.sandbox_general.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.management.id
  }
}

resource "azurerm_public_ip" "management" {
  name                = "pip-cortex-management-dev"
  location            = var.location
  resource_group_name = var.management_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_linux_virtual_machine" "management" {
  name                = "vm-cortex-management-dev"
  location            = var.location
  resource_group_name = var.management_rg_name
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.management.id,
  ]
  disable_password_authentication = true
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.management_vm.public_key_openssh
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

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.management_rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.management_rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = var.management_rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "link-kv-sandbox-dev"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = data.azurerm_virtual_network.sandbox.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob-sandbox-dev"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = data.azurerm_virtual_network.sandbox.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr-sandbox-dev"
  resource_group_name   = var.management_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = data.azurerm_virtual_network.sandbox.id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-cortex-dev"
  location            = var.location
  resource_group_name = var.app_rg_name
  subnet_id           = data.azurerm_subnet.sandbox_private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-cortex-dev"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-blob-cortex-dev"
  location            = var.location
  resource_group_name = var.app_rg_name
  subnet_id           = data.azurerm_subnet.sandbox_private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-blob-cortex-dev"
    private_connection_resource_id = azurerm_storage_account.this.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pe-acr-cortex-dev"
  location            = var.location
  resource_group_name = var.app_rg_name
  subnet_id           = data.azurerm_subnet.sandbox_private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-acr-cortex-dev"
    private_connection_resource_id = azurerm_container_registry.this.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }
}
