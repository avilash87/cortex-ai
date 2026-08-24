# Bootstrap: management group

One-time, manually-run config that places your subscription under a
`mg-cortex-ai` management group directly beneath the tenant root group —
models the Cloud Adoption Framework landing-zone pattern (policy/RBAC
inheritance from a management group down to subscriptions) at POC scale.

Local state, applied by you via `az login` — same shape as
`infra/bootstrap/tfc-oidc/`.

## Steps (run these yourself)

1. **Elevate your own access first** — by default even the tenant creator
   often isn't granted Azure RBAC at the tenant root scope, only Entra ID
   Global Administrator. You need one to manage the other. Pick one:
   - Portal: Microsoft Entra ID → Properties → toggle **"Access management
     for Azure resources"** to Yes.
   - CLI equivalent:
     ```bash
     az rest --method post \
       --url "https://management.azure.com/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"
     ```
   Either grants your signed-in Global Administrator the **User Access
   Administrator** role at scope `/` (tenant root). This is a real,
   standing role assignment — not time-limited — so tidy it up afterward
   if you don't want it lingering:
     ```bash
     az role assignment delete --assignee <your-object-id> --role "User Access Administrator" --scope /
     ```
2. Review and apply:
   ```bash
   cd infra/bootstrap/management-group
   terraform init
   terraform plan     # creates 1 management group + 1 subscription association
   terraform apply
   ```
3. Verify: Azure Portal → Management Groups, or
   `az account management-group list -o table`.

## Production design (described, not built here)
At real scale (Lloyds-style), this tier would be `Tenant Root Group` →
`Platform` / `Landing Zones` / `Sandbox` / `Decommissioned` management
groups, each with its own Azure Policy assignments, and **prod would live
in its own subscription** under `Landing Zones`, separate from `dev`/`test`
— giving hard billing, quota, and compliance boundaries per environment.
This POC skips the multi-tier hierarchy and the extra subscription: one
management group is enough to demonstrate the inheritance concept without
doubling the OIDC bootstrap and cost-tracking work for a 2-day exercise.

## Teardown (Phase 11)
```bash
cd infra/bootstrap/management-group
terraform destroy   # dissociates the subscription, then deletes the empty MG
```
