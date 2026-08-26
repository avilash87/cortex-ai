#!/usr/bin/env bash
# Run at the END of a study session to stop hourly billing.
# Safe to run from your own laptop - these are all Azure control-plane (ARM)
# calls, not Kubernetes API calls, so AKS's authorized_ip_ranges restriction
# doesn't apply to any of them. Idempotent: re-running is harmless if
# something's already stopped/deleted.
set -euo pipefail

TF_WORKSPACE="cortex-ai-dev"
AI_RG="rg-cortex-ai-dev"
AKS_NAME="aks-cortex-dev"
MGMT_RG="rg-cortex-management-dev"
VM_NAME="vm-cortex-management-dev"
BASTION_NAME="bastion-cortex-dev"

echo "== Stopping Cortex AI dev session (Terraform workspace: ${TF_WORKSPACE}) =="

echo "-> AKS node pool (${AKS_NAME})..."
aks_state=$(az aks show -g "$AI_RG" -n "$AKS_NAME" --query "powerState.code" -o tsv 2>/dev/null || echo "NotFound")
if [[ "$aks_state" == "Running" ]]; then
  az aks stop -g "$AI_RG" -n "$AKS_NAME"
else
  echo "   already ${aks_state}, skipping"
fi

echo "-> Management VM (${VM_NAME})..."
vm_state=$(az vm get-instance-view -g "$MGMT_RG" -n "$VM_NAME" \
  --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "NotFound")
if [[ "$vm_state" == "VM running" ]]; then
  az vm deallocate -g "$MGMT_RG" -n "$VM_NAME"
else
  echo "   already '${vm_state}', skipping"
fi

echo "-> Bastion (${BASTION_NAME})..."
if az network bastion show -g "$MGMT_RG" -n "$BASTION_NAME" &>/dev/null; then
  az network bastion delete -g "$MGMT_RG" -n "$BASTION_NAME" --yes
else
  echo "   already deleted, skipping"
fi

cat <<EOF

== Done ==
Costs stopped: AKS node + VM + Bastion (~\$0.50/hr while idle).

Drift note (Terraform workspace: ${TF_WORKSPACE}):
  - AKS stop / VM deallocate: zero Terraform drift, ever - power state
    isn't a Terraform-managed attribute for either resource.
  - Bastion delete: real drift. Terraform's state still expects it to
    exist; the next plan/apply against '${TF_WORKSPACE}' will propose
    recreating it. That's expected self-healing, not a problem to fix -
    but auto-apply is on, so an unrelated infra/ PR merging before you
    run session-start.sh will silently recreate (and re-bill) it.
EOF
