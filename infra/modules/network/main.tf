# Look up the existing spoke VNets created by the hub-network bootstrap.
# We use data sources so this module never owns or destroys those VNets.
data "azurerm_virtual_network" "ai" {
  name                = var.ai_spoke_vnet_name
  resource_group_name = var.ai_spoke_rg_name
}

data "azurerm_virtual_network" "sandbox" {
  name                = var.sandbox_spoke_vnet_name
  resource_group_name = var.sandbox_spoke_rg_name
}

# =============================================================================
# NSG — AI SPOKE
# One NSG per logical group of subnets. Rules follow the principle of
# least-privilege: deny everything not explicitly needed, allow what is.
# =============================================================================
resource "azurerm_network_security_group" "ai_aks" {
  name                = "nsg-ai-aks-dev"
  location            = var.location
  resource_group_name = var.ai_spoke_rg_name
  tags                = var.tags

  # AKS nodes need to talk to the API server (TCP 443) and between themselves.
  security_rule {
    name                       = "AllowAksApiServer"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
  }

  # AzureLoadBalancer tag = Azure's health probe traffic; always allow or LB breaks
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Deny all other inbound traffic not matched above
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_network_security_group" "ai_private_endpoints" {
  name                = "nsg-ai-pe-dev"
  location            = var.location
  resource_group_name = var.ai_spoke_rg_name
  tags                = var.tags

  # Private endpoints only accept traffic from within the VNet
  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_network_security_group" "sandbox" {
  name                = "nsg-sandbox-dev"
  location            = var.location
  resource_group_name = var.sandbox_spoke_rg_name
  tags                = var.tags

  # Sandbox is more permissive — allow SSH from VNet for WireGuard VM admin
  security_rule {
    name                       = "AllowSshFromVnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "22"
  }

  # WireGuard UDP port. Source is intentionally open (var default "*") because a
  # home broadband IP isn't static — narrowing this is still recommended once known.
  # trivy:ignore:AVD-AZU-0047 WireGuard requires internet-facing UDP by design;
  # exposure is limited to a single authenticated-handshake port, not a management port.
  security_rule {
    name                       = "AllowWireGuard"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_address_prefix      = var.wireguard_allowed_source_prefix
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "51820"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }
}

# =============================================================================
# ROUTE TABLES (UDR) — forced tunnelling through the hub firewall
# All spoke egress (0.0.0.0/0) points at the hub Azure Firewall private IP.
# Until the Firewall exists (Phase 9) the placeholder IP means traffic is
# dropped by Azure rather than forwarded — a deliberate security default.
# Set var.hub_firewall_private_ip to the real Firewall IP in Phase 9.
# =============================================================================
resource "azurerm_route_table" "ai" {
  name                          = "rt-ai-spoke-dev"
  location                      = var.location
  resource_group_name           = var.ai_spoke_rg_name
  bgp_route_propagation_enabled = false # prevent on-prem routes leaking into spoke
  tags                          = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.hub_firewall_private_ip
  }
}

resource "azurerm_route_table" "sandbox" {
  name                          = "rt-sandbox-spoke-dev"
  location                      = var.location
  resource_group_name           = var.sandbox_spoke_rg_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.hub_firewall_private_ip
  }
}

# =============================================================================
# SUBNETS — created inside the existing spoke VNets
# The bootstrap created the VNets; this module creates the subnets inside them.
# =============================================================================
resource "azurerm_subnet" "ai_aks" {
  name                 = "snet-aks-nodes"
  resource_group_name  = var.ai_spoke_rg_name
  virtual_network_name = data.azurerm_virtual_network.ai.name
  address_prefixes     = ["10.1.0.0/24"]
}

resource "azurerm_subnet" "ai_private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.ai_spoke_rg_name
  virtual_network_name = data.azurerm_virtual_network.ai.name
  address_prefixes     = ["10.1.1.0/24"]

  # Disable network policies so private endpoints can receive traffic on this subnet
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "ai_apim" {
  name                 = "snet-apim"
  resource_group_name  = var.ai_spoke_rg_name
  virtual_network_name = data.azurerm_virtual_network.ai.name
  address_prefixes     = ["10.1.2.0/24"]
}

resource "azurerm_subnet" "sandbox_general" {
  name                 = "snet-general"
  resource_group_name  = var.sandbox_spoke_rg_name
  virtual_network_name = data.azurerm_virtual_network.sandbox.name
  address_prefixes     = ["10.3.0.0/24"]
}

resource "azurerm_subnet" "sandbox_private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.sandbox_spoke_rg_name
  virtual_network_name = data.azurerm_virtual_network.sandbox.name
  address_prefixes     = ["10.3.1.0/24"]

  private_endpoint_network_policies = "Disabled"
}

# =============================================================================
# NSG + ROUTE TABLE ASSOCIATIONS
# NSG attached to subnet = all traffic in/out of that subnet is evaluated.
# Route table attached to subnet = all traffic OUT of that subnet uses these routes.
# =============================================================================
resource "azurerm_subnet_network_security_group_association" "ai_aks" {
  subnet_id                 = azurerm_subnet.ai_aks.id
  network_security_group_id = azurerm_network_security_group.ai_aks.id
}

resource "azurerm_subnet_network_security_group_association" "ai_pe" {
  subnet_id                 = azurerm_subnet.ai_private_endpoints.id
  network_security_group_id = azurerm_network_security_group.ai_private_endpoints.id
}

resource "azurerm_subnet_network_security_group_association" "sandbox" {
  subnet_id                 = azurerm_subnet.sandbox_general.id
  network_security_group_id = azurerm_network_security_group.sandbox.id
}

resource "azurerm_subnet_route_table_association" "ai_aks" {
  subnet_id      = azurerm_subnet.ai_aks.id
  route_table_id = azurerm_route_table.ai.id
}

resource "azurerm_subnet_route_table_association" "ai_pe" {
  subnet_id      = azurerm_subnet.ai_private_endpoints.id
  route_table_id = azurerm_route_table.ai.id
}

resource "azurerm_subnet_route_table_association" "ai_apim" {
  subnet_id      = azurerm_subnet.ai_apim.id
  route_table_id = azurerm_route_table.ai.id
}

resource "azurerm_subnet_route_table_association" "sandbox" {
  subnet_id      = azurerm_subnet.sandbox_general.id
  route_table_id = azurerm_route_table.sandbox.id
}
