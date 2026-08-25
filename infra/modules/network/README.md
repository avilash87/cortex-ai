# network module

Creates subnets, NSGs, and route tables (UDRs) inside the spoke VNets built by
the hub-network bootstrap. Called from infra/envs/dev and infra/envs/test.

Inputs:  spoke VNet names + RG names (looked up via data sources)
Outputs: subnet IDs consumed by AKS (Phase 6), APIM (Phase 8), private endpoints (Phase 9)

