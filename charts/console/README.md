# console Helm chart

Helm chart for deploying `services/console` to AKS. Built in Day 2 Phase 6.

Status: implemented (Phase 6) - Deployment, Service, ServiceAccount wired for
workload identity federation. `helm lint` and Trivy config scan both clean.

## Deploy
```bash
helm upgrade --install cortex-console . --namespace dev --create-namespace
```
The ServiceAccount name must stay `cortex-console` in the `dev` namespace -
it has to match `azurerm_federated_identity_credential.console_workload_identity`'s
subject (`system:serviceaccount:dev:cortex-console`) exactly, or workload
identity federation breaks silently (the pod just never gets a token, no
error at deploy time).
