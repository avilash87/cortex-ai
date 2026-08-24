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
- Phase 3 — VM, SSH key, Key Vault, ACR, Nexus (not started)
- Phase 4 — Docker (not started)
- Phase 5 — GitHub Actions CI (not started)
- Phase 6 — AKS + Helm (not started)
- Phase 7 — Entra SSO + client-credentials flow (not started)
- Phase 8 — Foundry + Guardrails + APIM (not started)
- Phase 9 — Private endpoints (not started)
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
