output "key_vault_id" {
  value = azurerm_key_vault.this.id
}

output "key_vault_name" {
  value = azurerm_key_vault.this.name
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "acr_id" {
  value = azurerm_container_registry.this.id
}

output "management_vm_id" {
  value = azurerm_linux_virtual_machine.management.id
}

output "management_vm_public_ip" {
  value = azurerm_public_ip.management.ip_address
}

output "management_vm_private_ip" {
  value = azurerm_network_interface.management.private_ip_address
}

output "ssh_private_key_secret_id" {
  value = azurerm_key_vault_secret.vm_ssh_private_key.id
}
