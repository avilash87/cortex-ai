output "client_ids" {
  description = "Application (client) ID per env — already set on workspaces, kept here for reference"
  value       = { for k, v in azuread_application.tfc : k => v.client_id }
}

output "tenant_id" {
  value = data.azurerm_subscription.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

output "workspace_ids" {
  description = "TFC workspace IDs"
  value       = { for k, v in tfe_workspace.env : k => v.id }
}
