output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "ingress_ip" {
  value = azurerm_public_ip.ingress.ip_address
}

# Option A: Use FQDN (requires domain_name_label in public IP)
output "grafana_url" {
  value = azurerm_public_ip.ingress.fqdn != null ? "http://grafana.${azurerm_public_ip.ingress.fqdn}" : "http://${azurerm_public_ip.ingress.ip_address}"
}
