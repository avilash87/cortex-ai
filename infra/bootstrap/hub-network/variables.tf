variable "location" {
  description = "Azure region for all hub resources"
  type        = string
  default     = "uksouth"
}

variable "subscription_id" {
  description = "Subscription GUID — same single sub used for the whole POC"
  type        = string
  default     = "5e131d1f-220b-4c15-a3b0-4d0009629b75"
}

variable "tags" {
  type = map(string)
  default = {
    owner       = "avilashj"
    env         = "dev"
    cost-centre = "cortex-ai-poc"
  }
}

# --- CIDR plan ---------------------------------------------------------------
# Rule: each spoke never overlaps with the hub or any other spoke.
# Bank practice: a central IPAM (IP Address Management) tool owns the master
# prefix; teams request a block from it. We hardcode here since it's a POC.
#
#  10.0.0.0/16   hub (Connectivity)
#    10.0.0.0/24   GatewaySubnet      (VPN/ExpressRoute gateway - name is fixed by Azure)
#    10.0.1.0/24   AzureFirewallSubnet (name is fixed by Azure)
#    10.0.2.0/24   dns-resolver-inbound
#    10.0.3.0/24   dns-resolver-outbound
#    10.0.4.0/24   management-tools   (Nexus, SonarQube, Aqua VMs/containers)
#
#  10.1.0.0/16   spoke-ai
#    10.1.0.0/24   aks-nodes
#    10.1.1.0/24   private-endpoints
#    10.1.2.0/24   apim
#
#  10.2.0.0/16   spoke-data
#    10.2.0.0/24   compute
#    10.2.1.0/24   private-endpoints
#
#  10.3.0.0/16   spoke-sandbox (dev work)
#    10.3.0.0/24   general
#    10.3.1.0/24   private-endpoints

variable "budget_amount_gbp" {
  description = "Monthly spend budget in GBP — alert fires at 80% actual and 100% forecasted"
  type        = number
  default     = 50
}

variable "budget_alert_email" {
  description = "Email address for cost budget alerts"
  type        = string
  default     = "avilashj87@gmail.com"
}

variable "hub_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "spoke_address_spaces" {
  type = map(list(string))
  default = {
    ai      = ["10.1.0.0/16"]
    data    = ["10.2.0.0/16"]
    sandbox = ["10.3.0.0/16"]
  }
}

# Defaults false - see the resolver's own comment in main.tf. Turned off
# 2026-09-02 after it turned out to be ~59% of a month's total project
# spend, running continuously with no stop/start of its own.
variable "create_dns_resolver" {
  type    = bool
  default = false
}
