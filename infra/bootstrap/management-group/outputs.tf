output "management_group_ids" {
  description = "All management group IDs — useful when writing policy assignments in later phases"
  value = {
    root           = azurerm_management_group.root.id
    platform       = azurerm_management_group.platform.id
    connectivity   = azurerm_management_group.connectivity.id
    management     = azurerm_management_group.management.id
    identity       = azurerm_management_group.identity.id
    landingzones   = azurerm_management_group.landingzones.id
    corp           = azurerm_management_group.corp.id
    online         = azurerm_management_group.online.id
    sandbox        = azurerm_management_group.sandbox.id
    decommissioned = azurerm_management_group.decommissioned.id
  }
}

output "landing_zone_rg_ids" {
  description = "Resource group IDs created by this landing-zone provisioner"
  value       = { for k, v in azurerm_resource_group.lz : k => v.id }
}
