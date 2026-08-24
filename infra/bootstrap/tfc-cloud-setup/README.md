# Bootstrap: Azure OIDC trust for HCP Terraform

One-time, manually-run config that lets the `cortex-ai-dev` and
`cortex-ai-test` TFC workspaces authenticate to Azure with **no stored
secret** (HCP Terraform "dynamic credentials" / workload identity
federation). Runs with local state, authenticated as *you* via `az login`
— it cannot use the `cortex-ai-*` TFC workspaces itself, since it's what
makes those workspaces able to auth in the first place.

Creates, per env: one Entra app registration + service principal, two
federated identity credentials (plan phase, apply phase), and a
`Contributor` role assignment scoped to that env's resource group only
(never subscription-wide).

## Steps (run these yourself)

1. Pre-create the two empty resource groups (the only resources *not*
   managed by Terraform in this whole project — everything below the RG
   is IaC, the RG boundary itself is a manual bootstrap exception, same
   pattern used for the state backend decision):
   ```bash
   az login
   az group create -n rg-cortex-ai-dev  -l <region> --tags owner=<you> env=dev  cost-centre=<cc>
   az group create -n rg-cortex-ai-test -l <region> --tags owner=<you> env=test cost-centre=<cc>
   ```
2. Review and apply this bootstrap:
   ```bash
   cd infra/bootstrap/tfc-oidc
   terraform init
   terraform plan     # read it - it creates 2 app registrations, 4 federated
                       # credentials, 2 role assignments
   terraform apply
   terraform output -json
   ```
3. In the HCP Terraform UI, for **each** workspace (`cortex-ai-dev`,
   `cortex-ai-test`), add these as workspace variables (category:
   **environment variable**, not Terraform variable; none are secret so
   "sensitive" is optional but fine to set anyway):
   - `TFC_AZURE_PROVIDER_AUTH` = `true`
   - `TFC_AZURE_RUN_CLIENT_ID` = the matching `client_ids.<env>` output
   - `ARM_TENANT_ID` = the `tenant_id` output
   - `ARM_SUBSCRIPTION_ID` = the `subscription_id` output
4. Re-run `terraform plan` in `infra/envs/dev` / `infra/envs/test` (via
   `terraform plan` locally, which now runs remotely in TFC) — it should
   authenticate to Azure successfully. Still an empty plan until Phase 1
   adds real resources.

## Teardown (Phase 11, or any time you want $0 idle footprint)
```bash
cd infra/bootstrap/tfc-oidc
terraform destroy   # removes the app registrations, federated creds, role assignments
az group delete -n rg-cortex-ai-dev  --yes
az group delete -n rg-cortex-ai-test --yes
```
