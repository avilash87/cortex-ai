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
  value = local.acr_login_server
}

output "acr_id" {
  value = local.acr_id
}

output "management_vm_id" {
  value = var.create_management_vm ? azurerm_linux_virtual_machine.management[0].id : null
}

output "management_vm_public_ip" {
  value = var.create_management_vm ? azurerm_public_ip.management[0].ip_address : null
}

output "management_vm_private_ip" {
  value = var.create_management_vm ? azurerm_network_interface.management[0].private_ip_address : null
}

output "ssh_private_key_secret_id" {
  value = var.create_management_vm ? azurerm_key_vault_secret.vm_ssh_private_key[0].id : null
}
