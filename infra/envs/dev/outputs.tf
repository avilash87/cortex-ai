output "key_vault_name" {
  value = module.keyvault.key_vault_name
}

output "management_vm_public_ip" {
  value = module.keyvault.management_vm_public_ip
}

output "bastion_public_ip" {
  value = module.keyvault.bastion_public_ip
}

output "ssh_private_key_pem" {
  value     = module.keyvault.ssh_private_key_pem
  sensitive = true
}
