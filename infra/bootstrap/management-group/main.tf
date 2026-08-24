# --- Tier 0: root anchor --------------------------------------------------
# Named "mg-cortex-ai" to scope policy to our org; in a real bank this would
# be the company's tenant-root or a top-level MG granted to the platform team.
resource "azurerm_management_group" "root" {
  name         = "mg-cortex-ai"
  display_name = "Cortex AI"
}

# --- Tier 1: Platform vs Landing Zones vs Sandbox vs Decommissioned --------
# Platform:      shared services operated by the platform team
# Landing Zones: workload subscriptions (corp = private, online = internet-facing)
# Sandbox:       dev/lab subscriptions with relaxed policy (your sub lives here)
# Decommissioned: retiring subscriptions, deny policy applied at this MG
resource "azurerm_management_group" "platform" {
  name                       = "mg-cortex-platform"
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "landingzones" {
  name                       = "mg-cortex-landingzones"
  display_name               = "Landing Zones"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "sandbox" {
  name                       = "mg-cortex-sandbox"
  display_name               = "Sandbox"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "decommissioned" {
  name                       = "mg-cortex-decommissioned"
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.root.id
}

# --- Tier 2: Platform children ---------------------------------------------
# Connectivity: hub VNet, Azure Firewall, ExpressRoute/VPN, DNS Private Resolver,
#               all private DNS zones - the single network choke-point.
# Management:   shared tooling used by all teams: SonarQube, Aqua/Trivy,
#               Nexus, Log Analytics workspace, Microsoft Defender for Cloud.
# Identity:     Entra Connect servers, PKI/CAs, Key Vault roots.
resource "azurerm_management_group" "connectivity" {
  name                       = "mg-cortex-connectivity"
  display_name               = "Connectivity"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "management" {
  name                       = "mg-cortex-management"
  display_name               = "Management"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "identity" {
  name                       = "mg-cortex-identity"
  display_name               = "Identity"
  parent_management_group_id = azurerm_management_group.platform.id
}

# --- Tier 2: Landing Zone children -----------------------------------------
# Corp:   private, VNet-connected workloads (AI platform, data platform).
#         Spoke VNets peer to the Connectivity hub; all traffic inspected
#         by the hub firewall before crossing platform boundaries.
# Online: internet-facing services; separate policy allowing public ingress.
resource "azurerm_management_group" "corp" {
  name                       = "mg-cortex-corp"
  display_name               = "Corp"
  parent_management_group_id = azurerm_management_group.landingzones.id
}

resource "azurerm_management_group" "online" {
  name                       = "mg-cortex-online"
  display_name               = "Online"
  parent_management_group_id = azurerm_management_group.landingzones.id
}

# --- Subscription placement ------------------------------------------------
# Placed under mg-cortex-corp (corp landing zone, private VNet-connected workloads).
# In production each concern below gets its own subscription vended here:
#   sub-cortex-ai-dev/prod → mg-cortex-corp
#   sub-connectivity       → mg-cortex-connectivity
#   sub-management         → mg-cortex-management
# POC simulates that boundary through RG naming; all RGs share this one sub.
resource "azurerm_management_group_subscription_association" "cortex_ai" {
  management_group_id = azurerm_management_group.corp.id
  subscription_id     = "/subscriptions/${var.subscription_id}"
}

# --- Landing zone resource groups ------------------------------------------
# Created here (not manually, not in tfc-oidc) because this bootstrap IS the
# landing zone provisioner. In a real bank a vending automation would create
# the subscription and its initial RGs atomically from a service catalog request.
resource "azurerm_resource_group" "lz" {
  for_each = {
    dev  = { env = "dev", tags = merge(var.tags_base, { env = "dev" }) }
    test = { env = "test", tags = merge(var.tags_base, { env = "test" }) }
  }
  name     = "rg-cortex-ai-${each.key}"
  location = var.location
  tags     = each.value.tags
}
