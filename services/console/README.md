# console

Single FastAPI app hosting all Cortex AI console features (per CLAUDE.md,
one console rather than separate apps):
- sandbox self-service (create a service identity for local testing)
- prod-access request (create an Entra app registration, return app/client id)
- usage/cost dashboard
- chat-cost demo and embedding/similarity demo (both call Foundry through APIM)

Containerized in Day 1 Phase 4; SSO and the client-credentials flow land in
Day 2 Phase 7; the AI-backed features land in Day 2 Phase 8.

Status: Phase 4 skeleton only — `/health` + `/` endpoints, multi-stage
non-root Dockerfile, docker-compose for local run. None of the actual
console features listed above are implemented yet.

## Local run
```bash
docker compose up --build
curl http://localhost:8000/health
```

## Nexus-proxied build (on the management VM, once WireGuard is up)
```bash
docker build --build-arg BASE_IMAGE=10.3.0.4:8082/library/python:3.12-slim -t cortex-console .
```
