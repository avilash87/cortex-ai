# nexus placement decision

CLAUDE.md requires every Docker base image, package install, and Terraform
provider pull to go through Nexus Repository — never straight to Docker
Hub, npm, PyPI, or the public Terraform Registry.

For this 2-day POC, Nexus OSS is **not** a Terraform-managed resource here.
It runs as a Docker Compose service on the same VM built in Day 1 Phase 3
(the SSH-key exercise VM), powered on only when in use, to avoid paying for
a second standing host. Docker/pip/npm/Terraform CLI on that VM are pointed
at the Nexus proxy repos once it's installed.

**Known POC deviation, flagged until Phase 3 lands**: anything built before
Phase 3 (this Phase 0 scaffold, and the Terraform Registry provider pulls
Terraform itself needs to run `init`/`validate`) still pulls direct from
the public registry.

Status: not yet implemented (lands in Phase 3).
