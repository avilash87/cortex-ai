# Cortex AI POC — Tutorial & Interview Notes

Living, append-only notes. One section per phase: **Concept** (plain-terms
explanation), **What we built** (and why), **Interview tips** (likely
questions + our comprehension-check answers). Never edit a past phase's
section — only add to it if we revisit that topic later.

## Contents
- [Phase 0 — Tooling, login, repo scaffold, remote TF state](#phase-0)
- [Phase 0b — Azure OIDC bootstrap for HCP Terraform](#phase-0b)
- [Phase 0c — Management group](#phase-0c)
- [Phase 0d — Bank-scale landing zone: full MG hierarchy + hub-and-spoke networking](#phase-0d)
- Phase 1 — Networking (not started)
- Phase 2 — IAM (not started)
- Phase 3 — VM, SSH key, Key Vault, ACR, Nexus, WireGuard (not started)
- Phase 4 — Docker (not started)
- Phase 5 — GitHub Actions CI/CD (not started)
- Phase 6 — AKS + Helm + container policy (not started)
- Phase 7 — Entra SSO + client-credentials flow (not started)
- Phase 8 — Foundry + Guardrails + APIM (not started)
- Phase 9 — Private endpoints + Firewall + WAF + VPN Gateway (not started)
- Phase 10 — Observability (not started)
- Phase 11 — Teardown + summary (not started)

---

## Phase 0

### Concept
- An **Azure subscription** is the billing/scope boundary; a **resource
  group** is a logical container inside it that everything gets tagged and
  deleted together as. We haven't created either yet in this phase — Phase
  0 is just local scaffolding.
- **Terraform state** is Terraform's record of what it thinks exists in the
  real world. If two people (or two runs) write state at the same time
  without locking, you get corruption or drift. Keeping state **remote**
  (not a file on your laptop) and **locked** is the fix.
- **HCP Terraform (Terraform Cloud)** is a hosted backend: it stores state,
  locks it during runs, and — critically for our teaching rule of never
  auto-applying — makes you click "Confirm & Apply" in its UI/CLI before
  anything is created. That's a built-in safety net, not something we have
  to bolt on ourselves.
- A **Terraform Cloud workspace** is not the same thing as a local
  `terraform workspace` (a state-file switch within one config) — a TFC
  workspace is a whole separate execution context (its own variables,
  state, run history) tied to one working directory. `cortex-ai-dev` and
  `cortex-ai-test` are two TFC workspaces, one per environment.
- We chose TFC over a hand-bootstrapped Azure Storage Account backend
  because it also gives us the manual-approval gate and run history for
  free, and the user already had a TFC account set up.

### What we built
- Repo layout matching CLAUDE.md's structure (not the flatter layout the
  original source plan suggested):
  `infra/modules/{network,foundry,apim,aks,keyvault,nexus,observability}/`,
  `infra/envs/{dev,test,prod}/` (prod intentionally empty),
  `services/console/`, `charts/console/`, `policy/{opa,guardrails}/`,
  `docs/adr/`, `.github/workflows/`.
- Each module/env folder got a README stating its purpose and which future
  phase builds it — so the empty scaffold is still legible.
- `docs/adr/0001-poc-scope.md` records the scope decisions (dev+test only,
  HCP Terraform from day one, Nexus deferred to Phase 3, everything else
  in CLAUDE.md stays in force).
- This file (`docs/TUTORIAL.md`) itself.
- Tooling check found `terraform` (v1.15.8) and `gh` already installed;
  `az`, `docker`, `kubectl`, `helm` are missing on this machine and need to
  be installed before later phases (see chat for install commands — not
  run automatically, since installing system packages needs your sudo
  approval).
- `infra/envs/dev/backend.tf` / `infra/envs/test/backend.tf` (added once
  the TFC org name was confirmed) point at the `cortex-ai-dev` /
  `cortex-ai-test` workspaces via a `cloud {}` block.

### Interview tips
- **"Why remote state?"** — avoid local state loss/corruption, enable
  locking so concurrent runs don't race, enable team/CI access without
  passing a state file around.
- **"local terraform workspace vs Terraform Cloud workspace — what's the
  difference?"** — a classic trip-up. Local workspace = a named state
  file within one config directory. TFC workspace = an entire separate
  run/state/variable context, usually one per environment or component.
- **"plan vs apply"** — plan is a dry-run diff against current state;
  apply executes it. Never skip reading the plan.
- **"Why HCP Terraform over a storage-account backend?"** — storage
  account backend gives you state + locking only; TFC additionally gives
  you a hosted run history, a manual approval gate, and (later, if
  needed) policy-as-code via Sentinel — useful even for a solo lab because
  it enforces the "always review before apply" habit structurally.

### Comprehension check (answer before Phase 1)
1. What's the difference between a local `terraform workspace` and a
   Terraform Cloud workspace?
2. Why do we keep Terraform state remote and locked, even on a solo
   two-day project with no teammates?

---

## Phase 0b

### Concept
- HCP Terraform runs execute on HashiCorp's infrastructure, not yours —
  they need their own way to prove their identity to Azure. **Dynamic
  credentials** (HCP Terraform's OIDC workload identity federation) issue
  a short-lived Azure token per run instead of using a stored client
  secret.
- The trust is a one-way statement configured on an Entra ID **App
  Registration**: "trust OIDC tokens issued by `https://app.terraform.io`
  whose `subject` claim matches this exact TFC organization/project/
  workspace/run-phase." That's a **Federated Identity Credential**.
- Each *run phase* (`plan`, `apply`) gets its own federated credential
  because the subject claim includes `run_phase` — so you need 2 per
  workspace, 4 total for dev+test.
- **App Registration vs Managed Identity**, revisited: a managed identity
  is for an Azure-hosted resource proving its own identity *to* Azure; an
  app registration + federated credential is for an **external** OIDC
  issuer (TFC, GitHub Actions, etc.) proving identity *into* Azure. Same
  underlying OAuth client-credentials-style flow, different direction.
- **Least privilege via scope, not just role**: the SPN gets `Contributor`
  — a fairly broad role — but scoped to *one resource group only*, not
  the subscription. Blast radius if the dev credential were ever misused
  is capped to `rg-cortex-ai-dev`.
- Chicken-and-egg problem: TFC can't create the very credential it needs
  to authenticate to Azure. So this bootstrap runs with **local state**,
  authenticated as you via `az login` — a deliberate, documented exception
  to "everything is a TFC-managed workspace," same shape as the ADR 0001
  scope-decision pattern.

### What we built
- `infra/bootstrap/tfc-oidc/` — a small local-state Terraform config
  (`azuread` + `azurerm` providers) creating, per env: one
  `azuread_application` + `azuread_service_principal`, two
  `azuread_application_federated_identity_credential` (plan + apply), and
  one `azurerm_role_assignment` (Contributor, scoped to that env's RG,
  looked up via a `data "azurerm_resource_group"` — never created/owned
  by this bootstrap).
- Decision: **two separate app registrations** (`cortex-ai-tfc-dev`,
  `cortex-ai-tfc-test`), not one shared app with two credentials — keeps
  dev and test credentials fully independent.
- Decision: resource groups `rg-cortex-ai-dev` / `rg-cortex-ai-test` are
  pre-created manually via `az group create` (documented in the
  bootstrap's README) — the RG boundary is the manual exception, Terraform
  owns everything inside it.
- Validated locally (`terraform fmt`, `init -backend=false`, `validate`) —
  not applied yet; that's a real-Azure-resource step for you to run and
  review, per the "never auto-apply" rule.

### Interview tips
- **"Why not just use a client secret?"** — secrets need rotation, can
  leak in logs/CI config, and are a standing credential that works from
  anywhere. A federated credential only exchanges for a token when a
  request arrives with a token from the *exact* trusted issuer+subject —
  nothing to leak, nothing to rotate.
- **"What's in the subject claim and why does it matter?"** —
  `organization:<org>:project:<project>:workspace:<workspace>:run_phase:<plan|apply>`
  — it's how Azure knows this token request came from *this specific*
  workspace's *this specific* run phase, not just "some TFC run somewhere."
- **"Why scope Contributor to a resource group instead of the
  subscription?"** — least privilege / blast-radius containment; a classic
  security-review question.
- **Comprehension check answers (recap):** local `terraform workspace` =
  a state-file switch within one config dir; TFC workspace = a whole
  separate run/state/variable context. Remote+locked state matters solo
  too, in case you run from two machines/sessions or a run gets
  interrupted mid-write.

### Comprehension check (answer before Phase 1)
1. Why does each TFC run *phase* (plan vs apply) need its own federated
   credential, rather than one shared credential per workspace?
2. If someone got hold of the `cortex-ai-tfc-dev` service principal's
   token, what's the actual blast radius, and why?

---

## Phase 0c

### Concept
- **Management groups** sit above subscriptions in Azure's scope hierarchy:
  `Tenant Root Group` → management group(s) → subscriptions → resource
  groups → resources. Azure Policy and RBAC assigned at a management group
  **inherit down** to every subscription/RG/resource beneath it — the whole
  point is applying governance once instead of per-subscription.
- This is the real shape of a bank-scale "landing zone" (Cloud Adoption
  Framework pattern): `Platform` / `Landing Zones` / `Sandbox` /
  `Decommissioned` management groups, with **prod living in its own
  subscription** for hard billing/quota/compliance isolation from
  dev/test.
- **Entra ID roles vs Azure RBAC are two separate systems.** Being Global
  Administrator (an Entra ID role, about identity/tenant administration)
  does **not** automatically grant you any Azure RBAC role (about
  resource access). "Elevate access" is the documented, auditable bridge:
  a Global Admin can grant themselves `User Access Administrator` at the
  tenant root scope (`/`) specifically to bootstrap Azure RBAC/management
  groups. We hit exactly this gap (`AuthorizationFailed` reading
  management groups) before elevating.
- We built **one** management group hierarchy and placed the subscription
  under `mg-cortex-corp` (Landing Zones → Corp) — not Sandbox. The
  subscription runs a real project with private VNet connectivity; that
  makes it a Corp landing zone, not a sandbox. `mg-cortex-sandbox` exists
  in the hierarchy to show the tier and would hold a throwaway dev sub in
  production, but holds nothing in this POC.
- In a real bank there would be **separate subscriptions** for each concern:
  `sub-cortex-ai` under `mg-cortex-corp`, `sub-connectivity` under
  `mg-cortex-connectivity`, `sub-management` under `mg-cortex-management`.
  With one subscription we simulate that boundary through resource group
  naming (`rg-cortex-connectivity-*`, `rg-cortex-ai-*`) and document the
  gap explicitly.

### What we built
- Elevated access once (Entra ID toggle or `az rest ... elevateAccess`)
  to get `User Access Administrator` at tenant root — fixing the earlier
  `AuthorizationFailed` on `az account management-group list`.
- `infra/bootstrap/management-group/` — local-state Terraform
  (`azurerm_management_group` + `azurerm_management_group_subscription_association`)
  placing the existing subscription under `mg-cortex-ai`, directly beneath
  the tenant root group.
- Documented, not built: the multi-tier CAF hierarchy and a
  prod-only subscription — recorded as the production design in the
  bootstrap README.

### Interview tips
- **"What's the Azure scope hierarchy?"** — tenant root group →
  management groups (nested up to 6 levels) → subscriptions → resource
  groups → resources. Policy/RBAC assigned higher flows down.
- **"Why would a bank put prod in its own subscription instead of just a
  resource group?"** — subscriptions are the hard boundary for billing,
  regional/service quotas, and often compliance scope — resource groups
  don't give you that.
- **"Difference between Entra ID roles and Azure RBAC roles?"** — Entra
  ID roles (Global Admin, User Admin, etc.) govern the *directory*
  (users, groups, apps); Azure RBAC roles (Owner, Contributor, User
  Access Administrator) govern *Azure resource* access. Elevate access is
  the audited, one-directional bridge from the former to the latter.

### Comprehension check (answer before Phase 1)
1. Why doesn't being an Entra ID Global Administrator automatically let
   you manage management groups or assign Azure RBAC roles?
2. What real problem does putting prod in a separate subscription (under
   a `Landing Zones` management group) solve that a resource group
   can't?

---

## Phase 0d

### Concept — Bank-scale Azure landing zone: management groups + networking

#### Management group hierarchy (what a bank actually looks like)
```
Tenant Root Group
└── mg-cortex-ai           (our root — bank: company root)
    ├── mg-platform        (shared services, operated by platform team)
    │   ├── mg-connectivity  hub VNet, firewall, VPN/ER gateway, DNS resolver
    │   ├── mg-management    SonarQube, Aqua/Trivy, Nexus, Log Analytics, Defender
    │   └── mg-identity      Entra Connect, PKI/CAs, Key Vault roots
    ├── mg-landingzones    (workload subscriptions vended by the platform team)
    │   ├── mg-corp          private, VNet-connected — AI platform, data platform
    │   └── mg-online        internet-facing services, separate ingress policy
    ├── mg-sandbox         (dev/lab, relaxed policy — your subscription lives here)
    └── mg-decommissioned  (retiring subs get moved here; Deny policy kicks in)
```

**Why this structure?** Azure Policy and RBAC assigned at a management group
inherit down automatically. If you put "require private endpoints on all
storage accounts" at `mg-landingzones`, it applies to every subscription
under Corp and Online without re-assigning it per-subscription.
`mg-sandbox` can have a looser policy so developers can experiment without
triggering prod-grade controls.

#### On networking: hub-and-spoke (not per-platform, not flat)

**The question was: do we create one network per platform service, or one
for the whole tenant?** The bank answer is neither extreme — it's
**hub-and-spoke**:

- **Hub** (lives in the Connectivity subscription / `mg-connectivity`):
  one VNet per region containing: Azure Firewall, VPN/ExpressRoute Gateway,
  Azure DNS Private Resolver, and private DNS zones for every PaaS service
  family. This is the single choke-point for all traffic crossing platform
  boundaries or leaving to the internet/on-prem.
- **Spoke** (one per workload, in its own subscription under `mg-corp`):
  AI platform gets `vnet-spoke-ai`; data platform gets `vnet-spoke-data`.
  Each spoke peers to the hub — never directly to each other (spoke-to-spoke
  is blocked unless the firewall explicitly allows it).
- **Why not flat (one big VNet)?** No isolation. A misconfigured data
  platform pod can reach AI platform resources directly. No audit log of
  cross-platform traffic.
- **Why not fully separate per-platform?** Shared services (ExpressRoute
  costs £10k+/month, DNS zones need to be authoritative once for a given
  domain) cannot be duplicated cheaply. VPN/gateway transit is shared
  through the hub.

#### DNS: centralized, not per-spoke
All private DNS zones live in the Connectivity hub. The DNS Private Resolver
in the hub receives DNS queries from all spokes (spokes' custom DNS server =
resolver inbound endpoint IP). This means adding a private endpoint in any
spoke automatically resolves from the correct zone — no per-spoke zone
duplication, no split-brain.

#### Where shared tools (SonarQube, Aqua, Nexus) sit
In the Management subscription (`mg-management`), on the
`snet-management-tools` subnet in the hub (or a dedicated spoke peered to
the hub). Every team's pipeline reaches them through the hub firewall.
For the POC we run Nexus OSS via Docker Compose on the same VM in
`snet-management-tools`.

#### What the CIDR plan looks like (ours)
```
10.0.0.0/16  hub (rg-cortex-connectivity-dev)
  10.0.0.0/24  GatewaySubnet        (name fixed by Azure — VPN/ER gateway)
  10.0.1.0/24  AzureFirewallSubnet  (name fixed by Azure — Firewall)
  10.0.2.0/24  snet-dns-resolver-inbound
  10.0.3.0/24  snet-dns-resolver-outbound
  10.0.4.0/24  snet-management-tools (Nexus, SonarQube, Aqua)

10.1.0.0/16  spoke-ai   (rg-cortex-spoke-ai-dev)
  10.1.0.0/24  aks-nodes
  10.1.1.0/24  private-endpoints
  10.1.2.0/24  apim

10.2.0.0/16  spoke-data (rg-cortex-spoke-data-dev)
10.3.0.0/16  spoke-sandbox
```

### What we built
- Expanded `infra/bootstrap/management-group/` from one MG to the full
  10-MG CAF hierarchy (root → platform/{connectivity,management,identity},
  landingzones/{corp,online}, sandbox, decommissioned). The subscription
  is placed in `mg-sandbox` — correctly reflecting what it is.
- `infra/bootstrap/hub-network/` — hub VNet + all required subnets
  (GatewaySubnet, AzureFirewallSubnet, DNS resolver inbound/outbound,
  management-tools), three spoke VNets (ai, data, sandbox), bidirectional
  VNet peering hub↔each spoke, and an Azure DNS Private Resolver with an
  inbound endpoint in the hub — all in one local-state bootstrap config.
- **Lab-vs-production gap explicitly flagged:**
  - `use_remote_gateways = false` on spoke→hub peering (no real VPN/ER
    gateway yet; flip to `true` in production when the gateway lands).
  - No Azure Firewall resource yet (costly ~£1/hr+); its subnet exists and
    a UDR pointing `0.0.0.0/0` at the firewall private IP would be the next
    step in production (Phase 9 material).
  - No Azure Policy assignments yet — MG hierarchy is the foundation;
    policies land in later phases.

### Interview tips
- **"How do you structure Azure networking at scale?"** — hub-and-spoke.
  Connectivity subscription owns the hub (firewall, gateway, DNS); each
  workload subscription gets a spoke VNet peered to it. Traffic between
  platforms goes through the firewall for inspection, not directly.
- **"Why is DNS centralized?"** — private DNS zones need to be authoritative
  once per domain. If you duplicate them per-spoke they can diverge. The
  DNS Private Resolver in the hub means all spokes resolve consistently
  without needing a DNS server VM.
- **"What are GatewaySubnet and AzureFirewallSubnet?"** — subnet names
  that Azure requires to be exact strings for the respective services. A
  common exam/interview gotcha.
- **"What does `allow_gateway_transit = true` on the hub peering do?"** —
  it lets spoke VNets use the hub's VPN/ER gateway for on-prem connectivity
  without each spoke needing its own (very expensive) gateway.
- **"Subscription as a blast-radius boundary — explain."** — subscriptions
  have hard limits (resource quotas, billing, policy scope). A compromise
  of one workload subscription can't consume another subscription's quota
  or affect its billing. Resource groups don't give that.

### Comprehension check (answer before Phase 1)
1. A data platform team adds a private endpoint for their storage account
   in `vnet-spoke-data`. How does a pod in `vnet-spoke-ai` resolve its
   private DNS name, given the DNS resolver is only in the hub?
2. You have Azure Firewall in the hub but spoke-to-spoke traffic is still
   flowing directly. What configuration step is missing?

---

## Phase 0 — Complete: What We Actually Built End-to-End

> This section covers everything that happened across Phase 0a–0d in
> execution order: what the goal was, what we coded, gotchas we hit and
> why, and the resulting live state. Read this before Phase 1.

---

### The full picture in one diagram

```
GitHub repo (avilash87/cortex-ai)   ← your source of truth
  │
  ├─ infra/bootstrap/tfc-cloud-setup/   ← LOCAL state (chicken-and-egg)
  │     ↓ terraform apply
  │     ├── Entra ID App Registrations: cortex-ai-tfc-dev, cortex-ai-tfc-test
  │     ├── Federated Identity Credentials (plan + apply × 2 workspaces)
  │     ├── Contributor role on subscription (scoped)
  │     ├── TFC workspaces cortex-ai-dev / cortex-ai-test (VCS-driven, auto-apply OFF)
  │     ├── TFC workspace env vars (TFC_AZURE_PROVIDER_AUTH, ARM_*, etc.)
  │     └── GitHub OAuth VCS connection (HCP Terraform ↔ GitHub)
  │
  ├─ infra/bootstrap/management-group/  ← LOCAL state
  │     ↓ terraform apply
  │     ├── 10 management groups (full CAF hierarchy)
  │     ├── Subscription under mg-cortex-corp
  │     └── rg-cortex-ai-dev, rg-cortex-ai-test (landing zone RGs)
  │
  ├─ infra/bootstrap/hub-network/       ← LOCAL state
  │     ↓ terraform apply
  │     ├── vnet-hub-cortex-dev (10.0.0.0/16)
  │     ├── 3 spoke VNets: ai / data / sandbox
  │     ├── Hub ↔ spoke VNet peerings (bidirectional)
  │     ├── Azure DNS Private Resolver + inbound endpoint
  │     ├── rg-cortex-management-dev (empty shell for Phase 10)
  │     └── £50/month subscription budget with 80% + forecast alerts
  │
  └─ infra/envs/dev/   ← TFC REMOTE state (cortex-ai-dev workspace)
        ↓ terraform plan (runs in TFC)
        Empty plan — no Azure auth errors = OIDC wired correctly ✓
```

---

### Why three separate local-state bootstraps?

**The chicken-and-egg problem:** Normal Terraform uses TFC as the state backend.
But TFC needs Azure credentials to do anything, the Azure credentials need an
Entra app registration, and creating Entra objects *requires* Terraform to run
first. You can't put the thing that creates the backend *inside* the backend.

Solution: three small configs that run with **local state** authenticated by your
own `az login` session, and whose job is to create everything that the main TFC
workspaces depend on. Once done, the main workspaces take over for all future
Terraform work.

```
infra/bootstrap/            ← local state, run once manually by a human
  tfc-cloud-setup/          ← creates the TFC workspaces + Azure OIDC trust
  management-group/         ← creates the MG hierarchy + landing zone RGs
  hub-network/              ← creates hub+spoke networking + DNS + budget

infra/envs/dev|test/        ← remote state (TFC), where Phases 1-11 land
```

---

### tfc-cloud-setup — what it creates and why each piece exists

```hcl
# 1. Entra app registration — defines Cortex AI TFC as an "application" in Entra ID
resource "azuread_application" "tfc" { for_each = var.envs ... }

# 2. Service principal — the runnable identity attached to the app registration
resource "azuread_service_principal" "tfc" { ... }

# 3. Federated credential — the OIDC trust statement
#    "Trust tokens from app.terraform.io for THIS workspace, THIS run phase"
resource "azuread_application_federated_identity_credential" "plan" {
  subject = "organization:avilashj:project:Default Project:workspace:cortex-ai-dev:run_phase:plan"
  issuer  = "https://app.terraform.io"
}
# (same again for apply phase — different subject claim = separate credential)

# 4. Role assignment — what the SPN is allowed to DO in Azure
resource "azurerm_role_assignment" "tfc_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
}

# 5. TFC workspace — the remote execution environment + state store
resource "tfe_workspace" "env" {
  working_directory = "infra/envs/${each.key}"
  auto_apply        = false  # manual "Confirm & Apply" always required
  vcs_repo {
    identifier     = "avilash87/cortex-ai"
    oauth_token_id = var.tfc_vcs_oauth_token_id
    branch         = "master"
  }
}

# 6. TFC workspace variables — no copy-paste; reference outputs directly
resource "tfe_variable" "workspace" {
  # TFC_AZURE_PROVIDER_AUTH = "true"
  # TFC_AZURE_RUN_CLIENT_ID = <client_id from app registration above>
  # ARM_TENANT_ID / ARM_SUBSCRIPTION_ID
}
```

**How TFC OIDC auth flows at run time:**
```
TFC runs a plan/apply
  → requests OIDC token from app.terraform.io (its own JWT)
  → presents token to Azure AD token endpoint
  → Azure checks: is issuer "app.terraform.io"? ✓
                  does subject match the federated credential exactly? ✓
  → returns a short-lived Azure access token
  → TFC uses that token for all azurerm/azuread API calls
  → token expires; next run gets a fresh one
  → NO secret is stored anywhere
```

**Interview answer — why OIDC/federated credentials over a client secret:**
> "A client secret is a long-lived credential that has to be stored somewhere, rotated
> manually, and works from anywhere it's copied to. A federated credential is a trust
> statement — Azure will only issue a token when it receives a JWT from the exact
> trusted issuer with the exact expected subject claim. Nothing to store, nothing to
> rotate, and the token is scoped to a single run. If the issuer or subject doesn't
> match, the exchange fails."

---

### management-group — what it creates and why

```hcl
# The full 10-MG CAF hierarchy
resource "azurerm_management_group" "root"         { name = "mg-cortex-ai" }
resource "azurerm_management_group" "platform"     { parent = root }
resource "azurerm_management_group" "connectivity" { parent = platform }
resource "azurerm_management_group" "management"   { parent = platform }
resource "azurerm_management_group" "identity"     { parent = platform }
resource "azurerm_management_group" "landingzones" { parent = root }
resource "azurerm_management_group" "corp"         { parent = landingzones }
resource "azurerm_management_group" "online"       { parent = landingzones }
resource "azurerm_management_group" "sandbox"      { parent = root }
resource "azurerm_management_group" "decommissioned" { parent = root }

# Subscription placed under Corp (not Sandbox — this is a real project)
resource "azurerm_management_group_subscription_association" "cortex_ai" {
  management_group_id = azurerm_management_group.corp.id
  subscription_id     = "/subscriptions/5e131d1f-..."
}

# Landing-zone RGs — created here, not manually
resource "azurerm_resource_group" "lz" {
  for_each = { dev = {...}, test = {...} }
  name     = "rg-cortex-ai-${each.key}"
  location = "uksouth"
  tags     = { owner = "avilashj", env = each.key, cost-centre = "cortex-ai-poc" }
}
```

**Why the subscription is under `mg-cortex-corp`, not `mg-cortex-sandbox`:**
> "Sandbox is for throwaway developer experiments with relaxed policy. Our
> subscription runs a real project with private VNet connectivity and production-
> grade tooling. In a bank, anything that connects to the corporate network goes
> into a Corp landing zone subscription — that's what we're building."

**The `terraform import` lesson:**
When we ran the bootstrap, two RGs already existed in Azure from an earlier
manual `az group create` command. Terraform refused to create them (resource
with that ID already exists). Fix: `terraform import` brings an existing Azure
resource under Terraform management without destroying it.
```bash
terraform import 'azurerm_resource_group.lz["dev"]' \
  /subscriptions/.../resourceGroups/rg-cortex-ai-dev
```
In production this comes up when: a team manually created something before IaC
existed, or when recovering from lost state. Import is always safer than
deleting and recreating.

---

### hub-network — what it creates and why

```hcl
# Hub VNet — the central choke-point
resource "azurerm_virtual_network" "hub" {
  name          = "vnet-hub-cortex-dev"
  address_space = ["10.0.0.0/16"]
}

# Fixed-name subnets Azure requires (name must be EXACT)
resource "azurerm_subnet" "gateway"  { name = "GatewaySubnet" }      # VPN/ER
resource "azurerm_subnet" "firewall" { name = "AzureFirewallSubnet" } # Firewall

# DNS resolver subnets (delegated — Azure manages them, you don't attach NSGs)
resource "azurerm_subnet" "dns_inbound"  { delegated to Microsoft.Network/dnsResolvers }
resource "azurerm_subnet" "dns_outbound" { delegated to Microsoft.Network/dnsResolvers }

# Spoke VNets — one per workload, each peered to hub
resource "azurerm_virtual_network" "spoke" {
  for_each      = { ai = ["10.1.0.0/16"], data = ["10.2.0.0/16"], sandbox = ["10.3.0.0/16"] }
}

# Bidirectional peering — hub can forward traffic; spokes use hub's gateway
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  allow_forwarded_traffic = true
  allow_gateway_transit   = true   # hub acts as gateway for spokes
}
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  allow_forwarded_traffic = true
  use_remote_gateways     = false  # flip to true when real VPN/ER gateway exists
}

# DNS Private Resolver — centralises private endpoint name resolution
resource "azurerm_private_dns_resolver" "hub" { virtual_network_id = hub.id }
resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  subnet_id = dns_inbound.id   # <— this IP is what you set as DNS server on spokes
}

# Cost budget — alerts before you overspend
resource "azurerm_consumption_budget_subscription" "poc" {
  amount     = 50   # GBP
  time_grain = "Monthly"
  time_period { start_date = "${substr(timestamp(), 0, 7)}-01T00:00:00Z" }
  notification { threshold = 80;  threshold_type = "Actual" }
  notification { threshold = 100; threshold_type = "Forecasted" }
}
```

**Why DNS resolution from spokes works without per-spoke DNS zones:**
```
Pod in vnet-spoke-ai queries: storage123.privatelink.blob.core.windows.net
  → spoke's custom DNS server = hub DNS resolver inbound endpoint IP
  → resolver checks private DNS zones linked to the hub VNet
  → finds A record: 10.1.1.5 (private endpoint IP)
  → returns 10.1.1.5 to the pod
  → pod connects directly over the private network
```
No DNS zone duplication. Add one private DNS zone once in the hub; all spokes
resolve it automatically because they all point at the hub resolver.

---

### The GitHub + TFC pipeline wiring

```
Code push to avilash87/cortex-ai (master branch)
    │
    ├─ infra/** changed?
    │      ↓
    │  TFC workspace cortex-ai-dev (VCS-driven, auto-apply=false)
    │      → speculative plan on PR (shows diff as required PR check)
    │      → full plan on merge
    │      → human reads plan in TFC UI
    │      → human clicks "Confirm & Apply"
    │
    └─ services/** or charts/** changed?
           ↓
       GitHub Actions (Phase 5 — not yet built)
           → lint → test → build → Trivy → SonarQube → OPA → push to ACR
           → auto-deploy to dev namespace
           → manual approval → deploy to test namespace
```

**Key design principle:** infrastructure changes and application changes go through
completely separate pipelines. An application developer can never accidentally
apply an infrastructure change. A platform engineer can never accidentally
deploy application code.

---

### Gotchas we hit — worth remembering for the interview

| What failed | Why | Fix |
|---|---|---|
| `az account management-group list` → `AuthorizationFailed` | Global Admin ≠ Azure RBAC. Two separate permission systems. | `az rest --method post .../elevateAccess` |
| `github_branch_protection` failed | Requires GitHub Pro for private repos | Removed; enforced by GH Actions required status checks in Phase 5 instead |
| `tfe_oauth_client` → "Repository doesn't exist" | GitHub username `avilash87` ≠ TFC org name `avilashj` — wrong owner in the identifier | Fixed `github_owner` variable default |
| `terraform apply` → branch doesn't exist | Repo had no commits, so `master` branch didn't exist on GitHub | Pushed first commit before wiring VCS |
| `start_date = formatdate("YYYY-MM-01T...")` → invalid format verb | Terraform's `formatdate` doesn't allow literal `T` in format string | Used `substr(timestamp(), 0, 7)` instead |
| `push` rejected: file too large | Provider binaries and Terraform state were tracked before `.gitignore` was added | `git rm --cached` to untrack + orphan rebuild |
| `azurerm_resource_group.lz already exists` | RGs were created manually earlier; Terraform had no state entry for them | `terraform import` |

---

### Phase 0 — Interview cheat-sheet (10 questions)

**1. What is Terraform state and why does it matter?**
> Terraform state is the mapping between your config and real Azure resources.
> Without it, Terraform doesn't know what it has already created. If state is
> local, it gets lost when your laptop does, or corrupts if two runs execute at
> once. Remote state in TFC adds locking (only one run at a time) and shared
> access (CI and humans use the same state).

**2. What's the difference between a local `terraform workspace` and a TFC workspace?**
> Local workspace = a named `.tfstate` file within one config directory. TFC
> workspace = a completely separate execution context with its own variables,
> state, run history, and approval gate. Apples and oranges — the name is
> misleading.

**3. How does TFC authenticate to Azure without a stored secret?**
> OIDC workload identity federation. TFC gets a JWT from its own issuer, presents
> it to Azure AD, Azure validates the issuer URL and subject claim against a
> Federated Identity Credential on the app registration, then returns a
> short-lived access token. Nothing is stored. The token is scoped to one run.

**4. Why does each TFC run phase (plan vs apply) need its own federated credential?**
> Because the OIDC subject claim includes `run_phase`. Azure's trust statement
> says "trust tokens from this workspace AND this run phase". A plan token cannot
> be reused for apply — different claim, different trust rule, different credential.

**5. What is the Azure scope hierarchy?**
> Tenant Root Group → Management Groups (up to 6 levels) → Subscriptions →
> Resource Groups → Resources. Azure Policy and RBAC assigned at any level
> inherit down automatically.

**6. Why is the subscription under `mg-cortex-corp` and not `mg-cortex-sandbox`?**
> Sandbox is for experiments with relaxed policy. Our subscription runs private
> VNet-connected workloads against real services. Corp is the correct Landing Zone
> tier for that. Putting it in Sandbox would mean corp-grade Azure Policy
> assignments at `mg-cortex-corp` wouldn't apply to our resources.

**7. What is hub-and-spoke networking and why does a bank use it?**
> Hub = one VNet with Azure Firewall, DNS resolver, VPN/ER gateway — shared
> infrastructure. Spokes = one VNet per workload, peered to the hub. All cross-
> spoke traffic goes through the hub firewall for east-west inspection. All egress
> through the hub for south-north control. Shared services (ExpressRoute,
> centralized DNS) can't be cheaply duplicated per-workload.

**8. Why is DNS centralized in the hub?**
> Private DNS zones must be authoritative for a domain exactly once. If each
> spoke had its own copy, they'd diverge. The DNS Private Resolver in the hub
> receives all DNS queries from spokes (via custom DNS server setting) and
> resolves them against zones linked to the hub VNet. Add a private endpoint
> in any spoke → resolves correctly across all spokes automatically.

**9. What is `terraform import` and when do you need it?**
> `terraform import` takes an existing Azure resource (with a known resource ID)
> and adds a state entry for it without touching the resource itself. You need
> it when: infrastructure was created manually before IaC existed, Terraform
> state was lost, or (as happened here) the same resource was created by an
> earlier step. Safer than delete-and-recreate because the resource stays live.

**10. What's the difference between Entra ID roles and Azure RBAC roles?**
> Entra ID roles (Global Admin, User Admin) govern the *directory* — who can
> manage users, apps, groups. Azure RBAC roles (Owner, Contributor) govern
> *Azure resource* access — who can create/modify/delete Azure resources.
> Being Global Admin gives you zero Azure resource permissions by default.
> "Elevate access" is the bridge: it temporarily grants User Access Administrator
> at tenant root, letting you bootstrap Azure RBAC. Remove it afterward.

---

### What's live in Azure right now

| Resource | Name | Managed by |
|---|---|---|
| Entra App Registration (dev) | `cortex-ai-tfc-dev` | tfc-cloud-setup local state |
| Entra App Registration (test) | `cortex-ai-tfc-test` | tfc-cloud-setup local state |
| TFC workspace | `cortex-ai-dev` | tfc-cloud-setup local state |
| TFC workspace | `cortex-ai-test` | tfc-cloud-setup local state |
| Management group root | `mg-cortex-ai` | management-group local state |
| Management groups (×9) | see hierarchy above | management-group local state |
| Resource group (dev LZ) | `rg-cortex-ai-dev` | management-group local state |
| Resource group (test LZ) | `rg-cortex-ai-test` | management-group local state |
| Hub VNet | `vnet-hub-cortex-dev` | hub-network local state |
| Spoke VNets (×3) | `vnet-spoke-{ai,data,sandbox}-cortex-dev` | hub-network local state |
| DNS Private Resolver | `dnspr-hub-cortex-dev` | hub-network local state |
| Management tools RG | `rg-cortex-management-dev` | hub-network local state |
| Cost budget | `budget-cortex-ai-poc` | hub-network local state |

**Nothing is yet managed by TFC** (the `infra/envs/dev` workspace has an empty
plan). Phase 1 will be the first real TFC-managed resource.

---

### Phase 1 preview — what's coming

Phase 1 adds NSGs (Network Security Groups) and UDRs (User Defined Routes) to
the spoke subnets already created, and assigns the first Azure Policies at the
management group level. This is where the MG hierarchy and hub-and-spoke
network start being used for real governance.

**Before Phase 1 starts, answer these out loud:**
1. In the hub-and-spoke network, what prevents spoke-to-spoke traffic today
   (since there's no Firewall yet)?
2. Azure Policy is assigned at `mg-cortex-corp`. Our subscription is under
   `mg-cortex-corp`. What happens to a storage account created in
   `rg-cortex-ai-dev` if that policy says "deny public network access"?
3. What would you add to the hub-network bootstrap to enforce that all spoke
   VNet traffic goes through the hub firewall (even before the firewall exists)?
