# console

Single FastAPI app hosting all Cortex AI console features (per CLAUDE.md,
one console rather than separate apps):
- sandbox self-service (create a service identity for local testing)
- prod-access request (create an Entra app registration, return app/client id)
- usage/cost dashboard
- chat-cost demo and embedding/similarity demo (both call Foundry through APIM)

Containerized in Day 1 Phase 4; SSO and the client-credentials flow land in
Day 2 Phase 7; the AI-backed features land in Day 2 Phase 8.

Status: not yet implemented.
