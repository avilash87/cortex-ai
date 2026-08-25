output "managed_identity_id" {
  description = "Resource ID of the console managed identity — used in AKS pod identity binding (Phase 6)"
  value       = azurerm_user_assigned_identity.console.id
}

output "managed_identity_client_id" {
  description = "Client ID — set as AZURE_CLIENT_ID env var in the console container"
  value       = azurerm_user_assigned_identity.console.client_id
}

output "managed_identity_principal_id" {
  description = "Object ID — used to add further role assignments in later phases"
  value       = azurerm_user_assigned_identity.console.principal_id
}

output "prod_access_client_id" {
  description = "Application (client) ID returned to the user by the prod-access console feature"
  value       = azuread_application.prod_access.client_id
}

output "prod_access_tenant_id" {
  description = "Tenant ID — always needed alongside the client ID for OAuth flows"
  value       = azuread_application.prod_access.publisher_domain
}

output "persona_group_object_ids" {
  description = "Group object IDs — useful for assigning app roles in Phase 7 (SSO)"
  value       = { for k, v in azuread_group.persona : k => v.object_id }
}

output "persona_user_upns" {
  description = "UPNs for the test personas — needed to sign in and test SSO in Phase 7"
  value       = { for k, v in azuread_user.persona : k => v.user_principal_name }
  sensitive   = false
}
