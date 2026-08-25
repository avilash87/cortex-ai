# management VM tooling

Docker Compose configs for software that runs on `vm-cortex-management-dev`
but is **not** Terraform- or CI-managed — deliberately manual, ephemeral
tooling, matching the "power on only while studying" pattern from Phase 3.

This is a new top-level directory, not in CLAUDE.md's original repo layout
list — flagged here rather than silently added. `infra/modules/nexus/`
already established the precedent that non-Terraform, VM-hosted tooling
still needs a documented home in the repo; `ops/management-vm/` generalizes
that to WireGuard too, rather than stretching the `nexus` module folder to
cover an unrelated VPN concern.

## What's here

- `docker-compose.wireguard.yml` — WireGuard VPN server. Self-hosted stand-in
  for the P2S VPN Gateway Phase 9 builds with Azure's native service; same
  problem (reach private endpoints from a laptop), self-hosted instead of
  managed, at near-zero cost.
- `docker-compose.nexus.yml` — Nexus OSS artifact proxy (added in the next
  step of Phase 4).

## Deploying

The VM has outbound internet access (Phase 3 addendum — see
`docs/TUTORIAL.md`), so the simplest path is cloning this public repo
directly on the VM rather than pasting file contents through the Bastion
session:

```bash
git clone https://github.com/avilash87/cortex-ai.git
cd cortex-ai/ops/management-vm
docker compose -f docker-compose.wireguard.yml up -d
```

Get the generated laptop peer config (QR code + `.conf` file) with:
```bash
docker exec wireguard cat /config/peer_laptop/peer_laptop.conf
```
