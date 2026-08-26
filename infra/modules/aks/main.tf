# =============================================================================
# AKS CLUSTER
# Control plane on the Free tier (no cost); the node pool VM(s) are the only
# billable part. Azure CNI (not kubenet) so pods get real VNet IPs, routable
# for the private-endpoint connections Phase 8 (Foundry/APIM) will need.
# OIDC issuer + workload identity enabled so the console's existing
# user-assigned identity (mid-cortex-console-dev, Phase 2) can be federated
# to a Kubernetes ServiceAccount - no secret mounted into any pod, ever.
# Azure Policy add-on enabled here; Gatekeeper constraint templates mapping
# our existing policy/opa/ Rego are added in a follow-up piece.
# =============================================================================
resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-cortex-${var.env}"
  location            = var.location
  resource_group_name = var.rg_name
  dns_prefix          = "aks-cortex-${var.env}"
  tags                = var.tags

  sku_tier = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = var.aks_subnet_id
  }

  network_profile {
    network_plugin = "azure"
  }

  # Cluster's own control-plane identity (distinct from the kubelet identity
  # below, which is what nodes use to pull images).
  identity {
    type = "SystemAssigned"
  }
}

# The kubelet identity is auto-created by Azure alongside the cluster
# (distinct from the control-plane identity above) - this is what nodes
# actually use to pull container images, so it's what needs AcrPull, not
# the cluster's own identity.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
