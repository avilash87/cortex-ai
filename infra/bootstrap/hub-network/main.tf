data "azurerm_subscription" "current" {}

# ============================================================================
# HUB RESOURCE GROUP
# In production: sits in the Connectivity subscription (sub-connectivity-prod)
# under mg-cortex-connectivity. Here it's a resource group in our single sub.
# ============================================================================
resource "azurerm_resource_group" "hub" {
  name     = "rg-cortex-connectivity-dev"
  location = var.location
  tags     = var.tags
}

# ============================================================================
# HUB VNET
# ============================================================================
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-cortex-dev"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = var.hub_address_space
  tags                = var.tags
}

# GatewaySubnet — fixed name required by Azure for VPN/ER gateway
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.0.0/24"]
}

# AzureFirewallSubnet — fixed name required by Azure Firewall
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/24"]
}

# DNS Private Resolver inbound endpoint (receives DNS queries from spokes)
resource "azurerm_subnet" "dns_inbound" {
  name                 = "snet-dns-resolver-inbound"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "dns-resolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# DNS Private Resolver outbound endpoint (forwards unresolved queries to on-prem/custom DNS)
resource "azurerm_subnet" "dns_outbound" {
  name                 = "snet-dns-resolver-outbound"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.3.0/24"]

  delegation {
    name = "dns-resolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Management tools subnet — Nexus, SonarQube, Aqua/Trivy run here (Phase 3)
resource "azurerm_subnet" "management_tools" {
  name                 = "snet-management-tools"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.4.0/24"]
}

# ============================================================================
# SPOKE VNETS — one per platform, each peered to the hub
# In production each spoke lives in its own subscription; here they're all in
# the same sub, simulated as separate VNets with separate resource groups.
# ============================================================================
resource "azurerm_resource_group" "spoke" {
  for_each = var.spoke_address_spaces
  name     = "rg-cortex-spoke-${each.key}-dev"
  location = var.location
  tags     = merge(var.tags, { platform = each.key })
}

resource "azurerm_virtual_network" "spoke" {
  for_each            = var.spoke_address_spaces
  name                = "vnet-spoke-${each.key}-cortex-dev"
  location            = azurerm_resource_group.spoke[each.key].location
  resource_group_name = azurerm_resource_group.spoke[each.key].name
  address_space       = each.value
  tags                = merge(var.tags, { platform = each.key })
}

# Hub → Spoke peering (hub can initiate connections into the spoke)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                  = var.spoke_address_spaces
  name                      = "peer-hub-to-${each.key}"
  resource_group_name       = azurerm_resource_group.hub.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke[each.key].id

  # Hub forwards traffic on behalf of spokes (needed for firewall/gateway transit)
  allow_forwarded_traffic = true
  allow_gateway_transit   = true
}

# Spoke → Hub peering (spoke uses hub's gateway and firewall as its default route)
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                  = var.spoke_address_spaces
  name                      = "peer-${each.key}-to-hub"
  resource_group_name       = azurerm_resource_group.spoke[each.key].name
  virtual_network_name      = azurerm_virtual_network.spoke[each.key].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_forwarded_traffic = true
  use_remote_gateways     = false # set true once a real VPN/ER gateway lands in the hub
}

# ============================================================================
# DNS PRIVATE RESOLVER
# Centralised in the hub so every spoke resolves private endpoint names to
# private IPs without each spoke needing its own resolver or DNS zone links.
# ============================================================================
resource "azurerm_private_dns_resolver" "hub" {
  name                = "dnspr-hub-cortex-dev"
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  name                    = "ep-inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub.id
  location                = azurerm_resource_group.hub.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns_inbound.id
  }
}

# ============================================================================
# MANAGEMENT RESOURCE GROUP
# In production: sits in the Management subscription (sub-management-prod)
# under mg-cortex-management. Holds: central Log Analytics Workspace,
# Application Insights, Defender for Cloud settings, SonarQube, Nexus, Aqua.
# Phase 10 populates the Log Analytics Workspace and diagnostic settings.
# Phase 3 installs the tooling (Nexus/SonarQube) on the VM inside this RG.
# ============================================================================
resource "azurerm_resource_group" "management" {
  name     = "rg-cortex-management-dev"
  location = var.location
  tags     = merge(var.tags, { platform = "management" })
}

# ============================================================================
# COST GOVERNANCE
# Subscription-level budget with alerts. In a bank:
#   - Each project/team gets a budget set by the platform team at provisioning
#   - Alert contacts the team's cost-centre owner, not just the subscription owner
#   - Cost tags (cost-centre, env, owner) on every resource enable chargeback
#     reports grouped by tag in Azure Cost Management
# Production note: EA customers use Department/Account cost management with
# commitments and reservations; MCA direct (this account) uses billing profiles.
# The operational budget+alert pattern is identical regardless of agreement type.
# ============================================================================
resource "azurerm_consumption_budget_subscription" "poc" {
  name            = "budget-cortex-ai-poc"
  subscription_id = data.azurerm_subscription.current.id

  amount     = var.budget_amount_gbp
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.budget_alert_email]
  }
}
