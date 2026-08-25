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

output "gh_actions_client_id" {
  description = "Set as AZURE_CLIENT_ID in GitHub Actions environment secrets"
  value       = azuread_application.gh_actions.client_id
}

output "gh_actions_sp_object_id" {
  description = "Pass as gh_actions_sp_object_id to the IAM module in infra/envs/*/main.tf"
  value       = azuread_service_principal.gh_actions.object_id
}
