# Plan: Cortex AI — 2-Day Learning POC (merged with CLAUDE.md guardrails)

## TL;DR
Build the "Cortex AI" learning POC from the pasted master-prompt, but folded
into the existing enterprise conventions in CLAUDE.md rather than replacing
them: same repo layout, naming, Nexus chokepoint, OPA/Trivy/SonarQube gates,
mandatory Foundry Guardrails/RAI policy, Foundry Project (non-Hub), private
network access only. The POC's 3 console features (sandbox self-service,
prod app-registration request, cost/usage dashboard) map directly onto
CLAUDE.md's `services/console/` FastAPI app — build them there instead of as
separate apps. Chat/embedding demos call Foundry **through APIM**, not
directly, per CLAUDE.md.

Per user decision: **only Phase 0 is planned in full detail here**; Phases
1–11 are outlined at a high level and will each get their own detailed plan
when reached. Day 1 (Phases 0–5) is the committed core; Day 2 (6–11) is
stretch/showcase.

## Standing rules for the build agent (apply to every phase, not just Phase 0)
- Explain the concept(s) a phase teaches, in interview-ready terms, before
  writing any code.
- Generate code/config in small pieces; explain each piece; stop and let the
  user read it before applying.
- Never run `terraform apply`, `kubectl apply`/`helm install`, or `az`
  create/delete commands. Hand the user the exact command, explain what it
  does and what it will cost, and how to verify the result.
- After each phase, ask 2 short comprehension-check questions.
- Explicitly flag every place the lab differs from the CLAUDE.md production
  design (e.g. local `terraform plan` only vs HCP Terraform runs; a minimal
  Nexus proxy vs the real chokepoint; private endpoints today vs P2S VPN
  described but not built).
- Remind the user to `terraform destroy` at the end of each day; warn before
  creating anything that bills meaningfully (AKS, Azure OpenAI/Foundry,
  managed disks).
- No secrets in code or git — Key Vault + Workload Identity/OIDC only,
  consistent with both CLAUDE.md and the source doc's rule 8.
- **Maintain a living tutorial doc**: `docs/TUTORIAL.md`, updated at the end
  of every phase (not a one-off writeup). Each phase's entry follows the
  same template — teacher voice, written for future-you revisiting it: 
  1. *Concept* — plain-terms explanation of what this phase teaches, as if
     explaining to someone new (mirrors the source doc's Part D
     cheat-sheets style).
  2. *What we built* — the actual resources/files/commands for this phase,
     and why each choice was made (including any CLAUDE.md-vs-POC
     deviation flagged in that phase).
  3. *Interview tips* — likely questions on this topic and how to answer
     them, plus the 2 comprehension-check questions asked and their
     answers.
  Never overwrite prior phase entries — append only, so the doc becomes the
  full 12-phase narrative by the end.

## Phase 0 — Tooling, login, repo scaffold, remote TF state (full detail)

1. **Tooling check** (no deps): confirm `az`, `terraform`, `docker`,
   `kubectl`, `helm`, `gh` CLI versions installed; `az login` +
   `az account set --subscription <sub>`; confirm target subscription has
   Contributor access for the POC.
2. **Repo scaffold** (*depends on 1*): create the CLAUDE.md-defined layout,
   not the flat layout from the source doc:
   - `infra/modules/{network,foundry,apim,aks,keyvault,nexus,observability}/`
     (empty module folders with a placeholder `main.tf`/README stub each)
   - `infra/envs/dev/` and `infra/envs/test/` (both built for the POC;
     `prod` stays an empty placeholder — no prod env in this exercise)
   - `services/console/` (FastAPI app root — will host chat-cost, sandbox,
     prod-request, and dashboard features from the source doc)
   - `charts/console/` (Helm chart, built in Day 2 Phase 6)
   - `policy/opa/`, `policy/guardrails/` (empty now; populated in later
     phases — Conftest policies and Foundry RAI/Content-Safety config)
   - `docs/adr/` — first ADR: "POC scope: dev+test envs (no prod), HCP
     Terraform backend, Nexus hosted on the Phase 3 VM, private-endpoint
     -only networking"
   - `docs/TUTORIAL.md` — created now with a title, table of contents
     (Phase 0–11 headings, empty), and the per-phase template described
     above; Phase 0 fills in its own section before this phase closes out.
   - `.github/workflows/` (empty; CI built in Phase 5)
3. **HCP Terraform (Terraform Cloud) as remote backend** (*depends on 2*):
   user already has a TFC account/org — create a `cortex-ai-dev` and
   `cortex-ai-test` workspace (CLI-driven, not VCS-driven, to keep the
   "review before apply" workflow explicit), configure
   `infra/envs/dev/backend.tf` / `infra/envs/test/backend.tf` with the
   `cloud {}` block. HCP Terraform supplies remote state, locking, and a
   built-in manual "Confirm & Apply" gate — no Azure Storage Account
   bootstrap needed. `az login` + an Azure service principal/OIDC
   federation is still required so TFC runs can authenticate to Azure
   (workload identity federation, no stored client secret).
4. **Nexus placement decision recorded, build deferred to Phase 3**
   (*depends on 2*): Nexus OSS runs via Docker Compose on the same VM
   built in Day 1 Phase 3 (the SSH-key exercise VM), powered on only when
   in use. Add `infra/modules/nexus/README.md` now documenting this
   decision (no separate module/resource — it's software on the Phase 3
   VM, not new infra) and note every later Dockerfile/CI step that still
   pulls direct from a public registry as a flagged POC gap until Phase 3
   lands.
5. **`terraform fmt` + `validate`** on the bootstrap config; user runs
   `terraform login`, `terraform init`, `terraform plan` against the TFC
   workspace (apply still requires the user's manual confirmation in the
   TFC UI/CLI — consistent with "never auto-apply").
6. **Phase 0 comprehension check** (per standing rules): 2 questions on
   HCP Terraform's remote state/locking + why workload identity
   federation replaces a stored Azure credential for TFC runs.

## Phase 0b — Azure OIDC bootstrap for HCP Terraform (added, blocking Phase 1)
Discovered mid-Phase-0: TFC workspaces can't authenticate to Azure at all
without this, so it had to land before Phase 1 despite being IAM content.
- `infra/bootstrap/tfc-oidc/` — local-state Terraform (azuread+azurerm
  providers), applied manually by the user via their own `az login`.
- Two app registrations (`cortex-ai-tfc-dev`, `cortex-ai-tfc-test`), each
  with 2 federated identity credentials (plan + apply run phases), each
  with `Contributor` scoped to that env's resource group only.
- Resource groups `rg-cortex-ai-dev` / `rg-cortex-ai-test` are pre-created
  manually via `az group create` — the one manual exception; Terraform
  owns everything inside them from Phase 1 on.
- After apply, user sets TFC workspace variables per env:
  `TFC_AZURE_PROVIDER_AUTH=true`, `TFC_AZURE_RUN_CLIENT_ID=<client_id>`,
  `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.
- Validated locally (`fmt`, `init -backend=false`, `validate`) — not
  applied by the agent; teardown command documented in the bootstrap
  README for Phase 11.
- `docs/TUTORIAL.md` "Phase 0b" section added (OIDC/federated-credential
  concept, App Registration vs Managed Identity direction distinction,
  least-privilege-via-scope interview framing).

## Phase 0c — Management group bootstrap (added, models landing-zone pattern)
User asked whether we should use a management group + subscription vending
like a real bank landing zone, instead of just the default subscription.
- Checked account: billing type is MicrosoftCustomerAgreement/Individual
  (a second subscription is technically possible), but
  `az account management-group list` failed with `AuthorizationFailed` —
  Global Admin doesn't auto-grant Azure RBAC at tenant root.
- Decision: subscription is placed under **`mg-cortex-corp`** (Landing
  Zones → Corp), not sandbox. Cortex AI is a real project with private
  VNet connectivity — that's Corp. `mg-cortex-sandbox` exists in the
  hierarchy but holds nothing in this POC.
- `infra/bootstrap/management-group/` — local-state Terraform
  (`azurerm_management_group` + `azurerm_management_group_subscription_association`).
  Requires a one-time "elevate access" step (Entra ID Global Admin →
  `User Access Administrator` at tenant root `/`) before it can be applied
  — documented in the bootstrap README, with the cleanup command to
  remove that role assignment afterward if desired.
- Validated locally (`fmt`, `init -backend=false`, `validate`); not
  applied by the agent — real tenant-root-scope IAM change, user's to run.
- `docs/TUTORIAL.md` "Phase 0c" section added (scope hierarchy, Entra ID
  roles vs Azure RBAC, elevate-access bridge, why prod gets its own
  subscription in production).

## Phases 1–11 — outline only (detailed plans deferred until reached)

- **Day 1**
  1. Networking: spoke VNets (spoke-ai, spoke-sandbox), NSGs on each subnet,
     UDRs pointing 0.0.0.0/0 at a placeholder firewall IP (demonstrates
     the forced-tunnelling pattern without paying for a live firewall yet).
     Also assign first Azure Policies at mg-cortex-landingzones and
     mg-sandbox: enforce required tags, deny public endpoints on Key Vault
     and Storage — free, teaches MG policy inheritance immediately.
  2. IAM — **the most interview-valuable phase**: four Entra ID personas,
     groups, Azure RBAC, managed identity, service principal, app
     registration. Full Lloyds-style identity model:

     **Entra ID users (cloud-only; simulates on-prem AD sync in production)**
     - `admin-cortex@<tenant>` — Platform Admin persona
     - `svc-devops@<tenant>`   — DevOps Engineer persona
     - `dev-alice@<tenant>`    — Developer persona
     - `sec-audit@<tenant>`    — Security/Audit persona

     **Entra ID security groups (not M365 groups — RBAC needs security groups)**
     - `grp-cortex-platform-admins` → admin-cortex
     - `grp-cortex-devops`          → svc-devops
     - `grp-cortex-developers`      → dev-alice
     - `grp-cortex-security-audit`  → sec-audit

     **Azure RBAC role assignments (group-based, not user-based):**
     - platform-admins: Contributor + User Access Administrator on
       rg-cortex-ai-dev / rg-cortex-ai-test
     - devops: Contributor on dev/test; Reader on prod placeholder
     - developers: Reader on all infra; Contributor on console's own RG only
     - security-audit: Security Reader + Key Vault Reader (subscription scope,
       read-everything touch-nothing)

     **Infrastructure identities (for the console app and CI pipeline):**
     - One user-assigned managed identity for the console (avoids secrets
       entirely for Azure resource access)
     - One service principal with federated credential for GitHub Actions
       (same OIDC pattern as TFC; no stored secret)
     - One Entra app registration for the prod-access console feature
       (returns app id + client id to the requester — the exact feature
       from the original spec)

     **Production patterns described, not built (flag in tutorial):**
     - User provisioning via Entra Connect (on-prem AD sync) + HR feed
     - Group membership via ServiceNow ITSM joiner/mover/leaver workflows
     - PIM (Privileged Identity Management) for platform-admin and Owner
       roles — just-in-time elevation, approval workflow, time-limited,
       full audit log. Requires Entra P2 — we use direct assignment in
       the POC and note the gap explicitly.
     - Conditional Access ("require MFA + compliant device") — wired up
       in Phase 7 when the console app registration exists to protect.
  3. VM + Terraform-generated SSH key in Key Vault, storage account, ACR —
     `infra/modules/keyvault/` + a small compute module. VM access via
     Azure Bastion Basic (~$0.19/hr, destroy after use) for admin.
     **Also run WireGuard in Docker on this VM** — gives the laptop a
     virtual IP in the hub address space so all private endpoints in every
     spoke are reachable from the dev machine. WireGuard client DNS =
     hub DNS resolver inbound IP (already in hub-network bootstrap) →
     private endpoint names resolve to private IPs automatically. This is
     the self-hosted simulation of Atmos/P2S VPN, at zero extra cost.
     Also install Nexus OSS via Docker Compose on this VM; power VM down
     between sessions.
  4. Docker: multi-stage, non-root `services/console/Dockerfile`; docker
     compose for local run; base images pulled through Phase 3 Nexus proxy.
  5. **CI/CD pipelines — two separate, never crossed:**

     **Infrastructure pipeline (TFC VCS-driven):**
     After Phase 0, connect TFC workspaces to the GitHub repo in the TFC
     UI (VCS Integration → working directory = `infra/envs/dev` or `test`).
     Auto-apply stays OFF — manual "Confirm & Apply" is always required.
     - PR on `infra/**` → TFC speculative plan (shows diff as a required PR
       check) + GH Actions OPA/Conftest policy gate
     - Merge to main → TFC full plan → human reviews in TFC UI → manual
       apply → cortex-ai-dev applies
     - Promotion to test: separate manual TFC run in cortex-ai-test workspace
       (or a GH Actions workflow that triggers TFC API after dev succeeds
       and a GH Environments "test" protection rule approves)

     **Application pipeline (GitHub Actions on `services/**`, `charts/**`):**

     *CI (triggers on PR):*
     ```
     lint          → ruff (Python), hadolint (Dockerfile), helm lint
     test          → pytest with coverage
     build         → docker buildx (multi-stage, non-root, linux/amd64)
     scan:sast     → SonarQube (self-hosted on Management VM, Phase 3)
                     quality gate is a required PR check — fail = no merge
     scan:sca      → Trivy (filesystem scan: Python deps, OS packages)
                     Trivy also covers what Aqua does for container scanning
                     (Aqua = production/enterprise version of this pattern)
     scan:iac      → Trivy (Dockerfile + Helm chart misconfig detection)
                     + OPA/Conftest (custom policy rules in policy/opa/)
     scan:secret   → gitleaks (no secrets committed — CLAUDE.md rule)
     ```

     *CD (triggers on merge to main):*
     ```
     build + push  → docker buildx → push to ACR
                     image tagged: <git-sha> (immutable) + "dev" (mutable)
     deploy:dev    → helm upgrade --install in AKS dev namespace
                     (uses GH OIDC → Azure workload identity, no stored secret)
     gate:test     → GH Environments "test" protection rule — requires
                     manual approval from a named reviewer before test deploy
     deploy:test   → helm upgrade --install in AKS test namespace
     ```

     **Security toolchain — where each tool sits and what it does:**
     | Tool        | Type          | Stage       | Notes |
     |-------------|---------------|-------------|-------|
     | Nexus OSS   | Artifact proxy| Build       | Docker base images + pip pulled via Nexus |
     | SonarQube   | SAST + quality| PR CI       | Self-hosted on Management VM (Phase 3) |
     | Trivy       | Container + SCA + IaC | PR CI | Free; covers Aqua's core use cases |
     | Hadolint    | Dockerfile lint| PR CI      | Free, runs in GH Actions |
     | Ruff        | Python lint   | PR CI       | Free, fast |
     | OPA/Conftest| Policy as code| PR CI + TFC | Same Rego rules, two enforcement points |
     | Gitleaks    | Secret scan   | PR CI       | Prevents CLAUDE.md rule violation |
     | Aqua Security| Container/CSPM| Phase 9  | Commercial; Trivy is the free equivalent |
     | OWASP DepCheck| SCA        | Optional    | Supplements Trivy SCA if needed |

     **Lab-vs-production flags:**
     - SonarQube on the management VM = the POC approximation; in
       production it would be a dedicated SonarQube server or SonarCloud
       (SaaS) wired through APIM or private endpoint.
     - Aqua Security = enterprise licensing; Trivy is used for the POC
       and covers the same container + IaC + SCA scan categories.
     - No signed container images yet (Cosign/Notary) — note this as a
       production gap alongside the Trivy scan.

     **Azure Functions:** Can be added as an optional extension in Phase 8
     (alongside Foundry/APIM). The GH Actions CD pipeline would gain a
     `deploy:function` step alongside the Helm deploy. Not in the committed
     scope but the pipeline structure supports it with one extra job.
- **Day 2 (stretch)**
  6. AKS via Terraform (workload identity, Azure CNI) + Helm deploy of
     `charts/console/`. **Add Azure Policy add-on to AKS + Gatekeeper
     (OPA) admission controller** — policies in `policy/opa/`: no
     privileged containers, require resource limits, require non-root.
     These are the same Rego/Conftest policies as our PR gate, enforced
     in-cluster at admission time.
  7. Entra SSO (OIDC) in front of the console; client-credentials flow
     behind the prod-request feature. Users and groups already exist from
     Phase 2 — Phase 7 wires the console app registration to use them:
     assign Phase 2 groups as app roles (console.admin, console.user,
     console.readonly). Add a Conditional Access policy: require MFA for
     all users accessing the console app. Test the full E2E journey:
     WireGuard up → browse private console URL → Entra OIDC redirect →
     sign in as each persona → verify correct role and MFA prompt.
     Also test the P2S VPN Gateway path (Azure VPN Client + Entra auth)
     to contrast with WireGuard.
  8. Foundry Project (non-Hub) + Guardrails/RAI policy + APIM routing.
  9. Private networking: private endpoints on Key Vault/Storage/Foundry/ACR.
     **Azure Firewall Basic** in the hub (~£0.60/hr — create, learn,
     destroy same session). **Application Gateway with WAF v2** in front
     of the console. **Azure VPN Gateway Basic + Entra ID P2S auth**
     (~$0.04/hr) — teaches the production SSO-to-VPN pattern: user opens
     Azure VPN Client, gets redirected to Entra ID, authenticates, VPN
     comes up. Replaces/complements WireGuard from Phase 3 with the actual
     Azure-native pattern. Describe full P2S VPN design in tutorial.
  10. Observability: **central Log Analytics Workspace** in
      `rg-cortex-management-dev` (RG already created in hub-network
      bootstrap), App Insights wired to the same workspace, diagnostic
      settings on all resources pointing to central LAW (the corp pattern —
      one workspace per environment, all platforms send logs to it).
      One dashboard, one alert. Also: Microsoft Defender for Cloud free
      tier enabled on the subscription (single config, covers all RGs).
      Cost Management custom view grouping spend by `cost-centre` tag.
      Production gaps flagged: Sentinel (SIEM on top of LAW), Defender P2,
      EA chargeback/showback via billing hierarchy.
  11. Teardown + one-page "how I explain this project" summary.

## Firewall/WAF/Bastion/VPN decisions (locked)
- **Azure Firewall Basic**: yes, Phase 9 only; create + learn + destroy in
  same session. ~£0.60/hr. `AzureFirewallSubnet` already provisioned.
- **VPN Gateway**: skip. Azure Bastion Basic (~$0.19/hr) used for VM
  access in Phase 3; P2S VPN documented as production pattern.
- **WAF**: Application Gateway + WAF v2 in Phase 9 in front of the console.
  Teaches L7 routing, WAF OWASP rule sets, AppGW vs Front Door distinction.
- **Azure Policy**: starts in Phase 1 (tag + private-endpoint policies at
  MG level, free), continues into Phase 6 (AKS container policies via
  Azure Policy add-on + Gatekeeper/OPA).
- **Container policy**: Phase 6 (AKS), Azure Policy for Kubernetes
  (Gatekeeper) + `policy/opa/` Rego rules — no privileged containers,
  require resource limits, require non-root user.

## Relevant files
- [CLAUDE.md](CLAUDE.md) — source of merged non-negotiables (naming, tags,
  Nexus, OPA/SonarQube/Trivy gates, RAI guardrails, Foundry Project type,
  private-only networking, repo layout).
- `infra/envs/dev/backend.tf` (new) — TF state backend bootstrap.
- `services/console/` (new) — FastAPI console hosting all POC console
  features from the source doc.
- `policy/guardrails/` (new, later phase) — Foundry RAI/Content-Safety
  policy definitions, required before any model deployment is usable.
- `docs/TUTORIAL.md` (new) — living, append-only teaching notes + interview
  tips, one section per phase, updated at the close of every phase.
- `infra/bootstrap/tfc-oidc/` (new) — one-time local-state bootstrap:
  Azure OIDC trust (app registrations, federated credentials, scoped RBAC)
  so TFC workspaces can authenticate to Azure with no stored secret.
- `infra/bootstrap/management-group/` (new) — one-time local-state
  bootstrap: `mg-cortex-ai` management group, subscription associated to
  it, modeling the CAF landing-zone pattern at POC scale.

## Verification (Phase 0)
1. `az account show` returns the intended subscription.
2. `terraform fmt -check` and `terraform validate` pass in
   `infra/envs/dev/` and `infra/envs/test/`.
3. TFC workspaces `cortex-ai-dev` / `cortex-ai-test` exist, are **VCS-driven**
   (connected to the private GitHub repo, working directories set to
   `infra/envs/dev` and `infra/envs/test`, auto-apply OFF), and
   `terraform plan` runs successfully against them (confirm via TFC UI
   run list, not just local output).
4. Repo tree matches the CLAUDE.md layout exactly (spot check with
   `list_dir`).
5. User can articulate: why TFC remote state needs locking; why workload
   identity federation replaces a stored Azure credential for CI/TFC runs.
6. `docs/TUTORIAL.md` exists and its Phase 0 section is filled in following
   the Concept/What we built/Interview tips template.

## Decisions
- **Merge, don't replace**: CLAUDE.md's guardrails (Nexus, OPA, SonarQube,
  Trivy, RAI guardrails, Foundry Project non-Hub, private-only, HCP TF
  intent) stay in force; the source doc supplies the teaching workflow and
  the phase/feature content.
- **Single console app**: the doc's chat-cost app, sandbox console, and
  prod-access console are all features inside CLAUDE.md's one
  `services/console/` FastAPI app (matches "sandbox self-service, prod
  approval requests, usage/cost dashboard" already specified there),
  rather than separate apps.
- **APIM in the path**: chat and embedding calls go through APIM (token
  quotas/cost policy), not straight to Azure OpenAI/Foundry, per CLAUDE.md.
- **Naming/tags**: use CLAUDE.md's `rg-cortex-ai-<env>` (not the doc's
  `rg-cortex-<env>`) and tags `owner`/`env`/`cost-centre` (doc's `project`
  tag dropped unless the user wants it added as a 4th tag).
- **Env scope**: `infra/envs/dev/` and `infra/envs/test/` are both built;
  `prod` folder exists but stays empty. No prod environment in this POC.
- **HCP Terraform**: adopted from Phase 0 (user already has a TFC account)
  — remote state, locking, and manual apply confirmation all come from TFC
  workspaces rather than a hand-bootstrapped Azure Storage Account backend.
- **Nexus hosting**: Nexus OSS runs via Docker Compose on the Phase 3 VM
  (reused, not a dedicated resource), powered on only when in use, to keep
  cost near-zero while still practicing the proxy-chokepoint pattern.

## Further Considerations
1. **Tag scheme**: keep to CLAUDE.md's 3 tags, or also add the doc's
   `project=cortex-ai` tag? Low-cost either way — flagging so it's a
   conscious choice, not drift.
2. **Budget note**: with dev+test envs, a reused VM for Nexus, and nightly
   teardown, expect roughly $5-20 of the $50-100 budget used across both
   days — plenty of headroom if a session runs long or something needs a
   rebuild.
