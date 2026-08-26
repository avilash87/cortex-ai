output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "oidc_issuer_url" {
  description = "Used by the workload identity federated credential (envs/dev)"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive = true
}
