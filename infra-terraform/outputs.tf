output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_fqdn" {
  description = "FQDN of the AKS API server"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "pg_server_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.pg.fqdn
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.kv.vault_uri
}

output "acr_login_server" {
  description = "Login server URL of the ACR"
  value       = azurerm_container_registry.acr.login_server
}

