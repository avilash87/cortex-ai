package main

# Defense-in-depth, PR-time version of the Azure Policy already enforced at
# mg-cortex-corp ("Deny public network access on Key Vault/Storage"): catch
# the same mistake at review time instead of waiting for the TFC apply to
# fail with RequestDisallowedByPolicy. Two independent enforcement points,
# same rule — this is meant to be redundant with the Azure Policy, not a
# replacement for it.

denied_public_types := {
	"azurerm_key_vault",
	"azurerm_storage_account",
	"azurerm_container_registry",
}

deny contains msg if {
	some resource_type, name
	denied_public_types[resource_type]
	block := input.resource[resource_type][name][_] # Conftest wraps each resource block in an array
	block.public_network_access_enabled == true
	msg := sprintf("%s.%s explicitly sets public_network_access_enabled = true", [resource_type, name])
}

# Catches the attribute being omitted entirely too — Azure's actual default
# for these resource types is public access ON, so silence is not safe.
# Note: this can't distinguish "genuinely never written" from "set via a
# variable reference" (Conftest's HCL parser doesn't resolve either one) —
# every instance of this attribute in this codebase today is a literal, so
# that ambiguity doesn't false-positive in practice. If that ever changes,
# failing closed (forcing a human to look) is the right direction for a
# security control to be wrong in, not failing open.
deny contains msg if {
	some resource_type, name
	denied_public_types[resource_type]
	block := input.resource[resource_type][name][_]
	# `not block.x` is true for BOTH "x is absent" and "x is false" in Rego —
	# false is the compliant value here, so a plain `not` would wrongly flag
	# correctly-configured resources too. object.get with a sentinel default
	# is the idiom that actually distinguishes "absent" from "present and false".
	object.get(block, "public_network_access_enabled", "unset") == "unset"
	msg := sprintf("%s.%s has no public_network_access_enabled setting at all (Azure defaults this to public)", [resource_type, name])
}
