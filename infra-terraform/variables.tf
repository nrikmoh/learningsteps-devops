variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-learningsteps-devops"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "db_subnet_prefix" {
  description = "Address prefix for the database subnet"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "aks_node_vm_size" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D2s_v6"
}

variable "aks_node_count" {
  description = "Number of AKS worker nodes"
  type        = number
  default     = 1
}

variable "pg_server_name" {
  description = "Name of the PostgreSQL server (globally unique)"
  type        = string
  default     = "learningsteps-db-mk"
}

variable "pg_admin_login" {
  description = "Administrator login for PostgreSQL"
  type        = string
  default     = "pgadmin"
}

variable "pg_sku" {
  description = "SKU for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "acr_name" {
  description = "Name of the existing Azure Container Registry"
  type        = string
  default     = "nrikmohacr"
}

variable "kv_name" {
  description = "Name of the Key Vault (globally unique, 3-24 chars)"
  type        = string
  default     = "kv-learningsteps-mk"
}

variable "service_cidr" {
  description = "CIDR range for Kubernetes internal services"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes internal DNS"
  type        = string
  default     = "172.16.0.10"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project     = "learningsteps"
    environment = "dev"
    managed_by  = "terraform"
  }
}
