# keyvault module

Phase 3 foundation for the private landing zone:

- Key Vault with public network access disabled
- Terraform-generated VM SSH key; private key stored as a Key Vault secret
- Storage account with public network access disabled
- Premium ACR with private endpoint support
- Small management VM in the sandbox spoke, with public IP reserved for
	WireGuard UDP/51820 and SSH restricted to VNet traffic by the Phase 1 NSG
- Private endpoints and private DNS zones for Key Vault, Blob Storage, and ACR

The module consumes existing spoke subnets created by the Phase 1 network
module. Nexus and WireGuard software installation is a later VM configuration
step; no credentials are embedded in this module.

Status: Phase 3 implementation.
