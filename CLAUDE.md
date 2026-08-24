# Cortex AI — Project Conventions

## What this is
A governed gateway in front of Microsoft Foundry models, with a dependency
chokepoint (Nexus) on the build side and AI guardrails (Foundry Content
Safety) on the model side. APIM does OpenAI-compatible routing, token
quotas, and cost policy. A custom FastAPI console on AKS handles sandbox
self-service, prod approval requests, and a usage/cost dashboard.

## Non-negotiables
- No secrets in code, ever. Workload Identity / OIDC only.
- All Terraform applies go through HCP Terraform runs once we reach
  Phase 2. Local `terraform plan` is fine for review.
- Every PR must pass: Super-Linter, SonarQube quality gate, Trivy
  (container+IaC+SCA), OPA/Conftest policy checks, before merge.
- Every Dockerfile, package install, and Terraform provider pull goes
  through Nexus Repository — never directly to Docker Hub, npm, PyPI, or
  the public Terraform Registry. If you write a Dockerfile or CI step
  that reaches the public internet directly, stop and flag it instead.
- Every Foundry model deployment must have a Guardrails/RAI policy
  assigned before it's usable — no deployment ships without Prompt
  Shields and PII detection enabled at minimum. Flag this explicitly if
  you generate a deployment without one.
- Foundry resource type = Foundry Project (not Hub-based) unless I say
  otherwise.
- Public network access disabled on Foundry and Key Vault; private
  endpoints only.
- Guardrail/RAI policy config may not have full azurerm Terraform
  coverage yet — check current provider docs before assuming a resource
  exists; if it doesn't, use the azapi provider or an ARM template
  passthrough, and say clearly which you used and why.
- When you generate Terraform or Kubernetes YAML, stop after generating
  and let me review the diff before you run apply/kubectl. Never chain
  generate→apply in one unattended step.
- Naming: resource group `rg-cortex-ai-<env>`, tags `owner`, `env`,
  `cost-centre` on everything.

## Repo layout
infra/modules/{network,foundry,apim,aks,keyvault,nexus,observability}/
infra/envs/{dev,test,prod}/
services/console/          # FastAPI: sandbox, prod-request, dashboard
charts/console/
policy/opa/
policy/guardrails/         # RAI policy definitions, content-safety config
docs/adr/
.github/workflows/