# foundry module

Azure AI Foundry Project (non-Hub-based per CLAUDE.md) plus the
Guardrails/RAI policy (Prompt Shields, PII detection) that must be attached
before any model deployment is usable. Built in Day 2 Phase 8.

Guardrail/RAI policy config may lack full `azurerm` coverage — this module
will use `azapi` or an ARM passthrough if needed, and will say clearly which.

Status: not yet implemented.
