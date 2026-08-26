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
