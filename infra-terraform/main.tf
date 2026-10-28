terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id                 = "363cb92f-6ef5-4317-aedc-550b3478627f"
  resource_provider_registrations = "none"
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-learningsteps-devops"
  location = "westeurope"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "learningsteps-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "db" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
    }
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "learningsteps-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "learningsteps"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v6"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }
}

data "azurerm_container_registry" "acr" {
  name                = "nrikmohacr"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = data.azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

resource "azurerm_private_dns_zone" "pg" {
  name                = "private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "pg_link" {
  name                  = "pg-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.pg.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "random_password" "pg_password" {
  length  = 20
  special = true
}

resource "azurerm_postgresql_flexible_server" "pg" {
  name                          = "learningsteps-db-mk"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.db.id
  private_dns_zone_id           = azurerm_private_dns_zone.pg.id
  public_network_access_enabled = false
  administrator_login           = "pgadmin"
  administrator_password        = random_password.pg_password.result
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768

  lifecycle {
    ignore_changes = [zone, high_availability]
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-learningsteps-mk"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  purge_protection_enabled    = false
  rbac_authorization_enabled  = true
}

resource "azurerm_role_assignment" "user_kv_admin" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Administrator"
  scope                = azurerm_key_vault.kv.id
}

resource "azurerm_role_assignment" "aks_kv_secrets" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "Key Vault Secrets User"
  scope                            = azurerm_key_vault.kv.id
  skip_service_principal_aad_check = true
}
