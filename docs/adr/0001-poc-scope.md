# ADR 0001: POC scope

## Status
Accepted — 2026-08-23

## Context
Cortex AI's CLAUDE.md describes a full enterprise gateway (Nexus chokepoint,
OPA/SonarQube/Trivy PR gates, HCP Terraform, APIM, AKS, mandatory Foundry
Guardrails/RAI policy). This repo is being built as a 2-day, budget-capped
($50-100) hands-on learning exercise, not a production rollout.

## Decision
- Only `dev` and `test` environments are built; `prod` stays an empty
  placeholder.
- HCP Terraform (Terraform Cloud) is the remote backend from day one —
  remote state, locking, and manual apply confirmation, no hand-bootstrapped
  Azure Storage Account backend.
- Nexus OSS runs via Docker Compose on the Phase 3 VM (reused, not a
  dedicated resource), powered on only when in use.
- Everything else in CLAUDE.md (naming, tags, OPA/SonarQube/Trivy gates,
  Foundry Project non-Hub, mandatory Guardrails/RAI policy, private-only
  networking) stays in force.
- Everything is torn down (`terraform destroy`) at the end of each day.

## Consequences
Some CLAUDE.md production controls (a real Nexus instance, HCP Terraform's
"Phase 2" maturity gate, a P2S VPN) are approximated or deferred and must be
flagged explicitly wherever the lab differs from production — tracked in
`docs/TUTORIAL.md` phase by phase.
