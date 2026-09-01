output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "spoke_vnet_ids" {
  value = { for k, v in azurerm_virtual_network.spoke : k => v.id }
}

output "management_tools_subnet_id" {
  description = "Subnet where Nexus/SonarQube/Aqua land in Phase 3"
  value       = azurerm_subnet.management_tools.id
}

output "management_rg_name" {
  description = "RG for central Log Analytics, App Insights, Defender — populated in Phase 10"
  value       = azurerm_resource_group.management.name
}

output "dns_resolver_inbound_ip" {
  description = "Set as custom DNS server on spoke VNets and WireGuard client DNS - null when var.create_dns_resolver is false"
  value       = var.create_dns_resolver ? azurerm_private_dns_resolver_inbound_endpoint.hub[0].ip_configurations[0].private_ip_address : null
}
