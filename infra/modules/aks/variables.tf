variable "env" {
  type = string
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "rg_name" {
  description = "Resource group the cluster resource itself lives in (not the auto-generated MC_* node RG)"
  type        = string
}

variable "aks_subnet_id" {
  description = "Subnet for Azure CNI pod/node IPs - snet-aks-nodes from the network module"
  type        = string
}

variable "node_vm_size" {
  type    = string
  default = "Standard_B2s"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "acr_id" {
  description = "ACR resource ID - grants the kubelet identity AcrPull so nodes can pull cortex-console"
  type        = string
}

# Restricting to the management VM's static public IP rather than the dynamic
# home-broadband IP problem WireGuard already has: the self-hosted runner and
# any interactive kubectl/helm work both happen from that VM (via Bastion),
# so it's the one address that's actually stable and actually needs API access.
variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server's public endpoint"
  type        = list(string)
}
