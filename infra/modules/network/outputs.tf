output "ai_aks_subnet_id" {
  description = "Used by AKS node pool (Phase 6)"
  value       = azurerm_subnet.ai_aks.id
}

output "ai_private_endpoints_subnet_id" {
  description = "Used by private endpoints for Foundry, Key Vault, ACR, storage (Phases 3, 8, 9)"
  value       = azurerm_subnet.ai_private_endpoints.id
}

output "ai_apim_subnet_id" {
  description = "Used by APIM (Phase 8)"
  value       = azurerm_subnet.ai_apim.id
}

output "sandbox_general_subnet_id" {
  description = "Used by WireGuard VM + Nexus/SonarQube VM (Phase 3)"
  value       = azurerm_subnet.sandbox_general.id
}

output "sandbox_pe_subnet_id" {
  description = "Used by private endpoints in the sandbox spoke (Phase 9)"
  value       = azurerm_subnet.sandbox_private_endpoints.id
}
