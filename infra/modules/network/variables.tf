variable "location" {
  type    = string
  default = "uksouth"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Hub connectivity RG — the spoke VNets were created in this RG by the bootstrap
variable "hub_rg_name" {
  type    = string
  default = "rg-cortex-connectivity-dev"
}

# AI spoke: AKS nodes, private endpoints for Foundry/Key Vault/ACR, APIM
variable "ai_spoke_rg_name" {
  type    = string
  default = "rg-cortex-spoke-ai-dev"
}

variable "ai_spoke_vnet_name" {
  type    = string
  default = "vnet-spoke-ai-cortex-dev"
}

# Sandbox spoke: general dev/test workloads, WireGuard gateway VM
variable "sandbox_spoke_rg_name" {
  type    = string
  default = "rg-cortex-spoke-sandbox-dev"
}

variable "sandbox_spoke_vnet_name" {
  type    = string
  default = "vnet-spoke-sandbox-cortex-dev"
}

# Placeholder firewall private IP — exists in AzureFirewallSubnet once Phase 9 deploys it.
# Until then the route table is created but the UDR routes won't forward (no next-hop device).
# In production flip this to the real Azure Firewall private IP; no other change needed.
variable "hub_firewall_private_ip" {
  description = "Azure Firewall private IP in the hub (placeholder until Phase 9)"
  type        = string
  default     = "10.0.1.4"
}

# WireGuard needs internet-facing UDP since your laptop connects from a home
# broadband IP (not static, can't be pinned in advance). "*" is the accepted
# default for this single port; set to "<your-home-ip>/32" once known to narrow it,
# and re-narrow if your ISP changes your IP (dynamic IP is the common case in the UK).
variable "wireguard_allowed_source_prefix" {
  description = "Source CIDR/IP allowed to reach the WireGuard UDP port (51820)"
  type        = string
  default     = "*"
}
