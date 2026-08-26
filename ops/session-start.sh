#!/usr/bin/env bash
# Run at the START of a study session, opposite of session-stop.sh.
# Same idempotency/no-Bastion-needed reasoning as that script.
set -euo pipefail

TF_WORKSPACE="cortex-ai-dev"
AI_RG="rg-cortex-ai-dev"
AKS_NAME="aks-cortex-dev"
MGMT_RG="rg-cortex-management-dev"
VM_NAME="vm-cortex-management-dev"
BASTION_NAME="bastion-cortex-dev"

echo "== Starting Cortex AI dev session (Terraform workspace: ${TF_WORKSPACE}) =="

echo "-> Management VM (${VM_NAME})..."
vm_state=$(az vm get-instance-view -g "$MGMT_RG" -n "$VM_NAME" \
  --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "NotFound")
if [[ "$vm_state" != "VM running" ]]; then
  az vm start -g "$MGMT_RG" -n "$VM_NAME"
else
  echo "   already running, skipping"
fi

echo "-> AKS node pool (${AKS_NAME})..."
aks_state=$(az aks show -g "$AI_RG" -n "$AKS_NAME" --query "powerState.code" -o tsv 2>/dev/null || echo "NotFound")
if [[ "$aks_state" != "Running" ]]; then
  az aks start -g "$AI_RG" -n "$AKS_NAME"
else
  echo "   already running, skipping"
fi

echo "-> Bastion (${BASTION_NAME})..."
if az network bastion show -g "$MGMT_RG" -n "$BASTION_NAME" &>/dev/null; then
  echo "   already exists, skipping"
  bastion_exists=1
else
  bastion_exists=0
fi

cat <<EOF

== Done ==
VM + AKS are back (or already were).
EOF

if [[ "$bastion_exists" == "0" ]]; then
  cat <<EOF
Bastion was deleted at the end of the last session (Terraform workspace:
${TF_WORKSPACE}) - that's expected. Recreate it with:
  cd infra/envs/dev && terraform apply
(or it comes back automatically the next time any infra/ PR merges, since
auto-apply is on for '${TF_WORKSPACE}').
EOF
fi
