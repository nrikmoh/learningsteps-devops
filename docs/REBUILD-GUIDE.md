# Rebuild Guide: Lessons from `terraform destroy` + `terraform apply`

> **Purpose:** This document captures everything we learned when we tore down the entire LearningSteps infrastructure and rebuilt it from scratch using only code. It serves as a runbook for anyone (including future-me) who needs to recreate the environment.

## Why We Did This

To prove **reproducibility** — the idea that your entire infrastructure can be destroyed and recreated from code alone, with no manual portal clicking. This is a core DevOps principle.

## The 9 Lessons Learned

### 1. ACR Must Be a `resource`, Not a `data` Block
**Problem:** Our ACR (Azure Container Registry) was defined as a `data` block in Terraform, meaning Terraform only *read* it but didn't *manage* it. When we ran `terraform destroy`, the ACR survived — but when we ran `terraform apply` on a fresh state, Terraform couldn't find it.

**Fix:** Changed `data "azurerm_container_registry"` to `resource "azurerm_container_registry"` so Terraform creates and destroys it like everything else.

### 2. Resource Group Won't Delete If It Contains Lingering Resources
**Problem:** After destroying AKS, some resources (like load balancer IPs) lingered in the resource group. Terraform refused to delete the RG because it wasn't empty.

**Fix:** Added `prevent_deletion_if_contains_resources = false` to the `azurerm` provider features block. This tells Terraform to delete the RG even if stuff is still in it.

### 3. ACR Admin Password Rotates on Recreation
**Problem:** When ACR is destroyed and recreated, Azure generates a brand-new admin password. Our GitHub Secret `ACR_PASSWORD` still held the old one, so the CI/CD pipeline couldn't push Docker images.

**Fix:** After rebuild, manually update the GitHub Secret:
az acr credential show --name nrikmohacr --query "passwords[0].value" -o tsv

Then paste the new password into GitHub > Settings > Secrets > `ACR_PASSWORD`.

### 4. Service Principal Role Assignment Is Destroyed With the RG
**Problem:** The role assignment that lets our GitHub Actions Service Principal deploy to the resource group is scoped *to* that resource group. When the RG is destroyed, the role assignment goes with it.

**Fix:** After rebuild, re-grant the role:
az role assignment create --assignee "89baff57-b0ba-4ca1-aa7d-e9fafa3e4833" --role Contributor --scope "/subscriptions/363cb92f-6ef5-4317-aedc-550b3478627f/resourceGroups/rg-learningsteps-devops"


### 5. CSI Driver Gets a New Identity When Re-Enabled
**Problem:** The Azure Key Vault CSI driver addon creates a managed identity. When you disable and re-enable the addon (which happens on cluster rebuild), the identity changes. The old `userAssignedIdentityID` in `secretproviderclass.yml` becomes invalid, causing "Identity not found" errors.

**Fix:** After re-enabling the addon, get the new identity and update the manifest:
az aks show --name learningsteps-aks --resource-group rg-learningsteps-devops --query "addonProfiles.azureKeyvaultSecretsProvider.identity.objectId" -o tsv

Then grant it Key Vault access and update `k8s/secretproviderclass.yml`.

### 6. LoadBalancer Gets New Public IPs
**Problem:** Kubernetes LoadBalancer services get fresh public IPs from Azure on recreation. The old IPs in our documentation become stale.

**Fix:** Find the new IPs:
kubectl get svc -n learningsteps
kubectl get svc -n monitoring monitoring-grafana

### 7. Docker Images Are Deleted With ACR
**Problem:** When ACR is destroyed, all stored Docker images are deleted. After rebuild, the AKS deployment tries to pull an image that no longer exists.

**Fix:** Trigger a pipeline rebuild with an empty commit:
git commit --allow-empty -m "Rebuild Docker image after ACR recreation"
git push


### 8. Monitoring Namespace Is Destroyed With the Cluster
**Problem:** The `monitoring` namespace (and everything in it) lives inside the AKS cluster. When the cluster is destroyed, the namespace goes with it. Terraform doesn't manage Kubernetes namespaces.

**Fix:** Recreate the namespace and reinstall the Helm chart:
kubectl create namespace monitoring
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --values k8s/prometheus-values-lean.yml


### 9. The CSI Chicken-and-Egg Problem Returns
**Problem:** On a fresh cluster, the app pod needs the database connection string from Key Vault to start. But the CSI driver creates the Kubernetes secret *after* the pod starts. The pod crashes before the secret exists.

**Fix:** Seed the secret manually once:
$cs = az keyvault secret show --name pg-connection-string --vault-name kv-learningsteps-mk --query value -o tsv
kubectl create secret generic learningsteps-secrets --from-literal="database-url=$cs" -n learningsteps --dry-run=client -o yaml | kubectl apply -f -
After the pod starts successfully, CSI takes over and keeps the secret synced.

---

## Step-by-Step Rebuild Runbook

### Prerequisites
- Azure CLI installed and logged in (`az login`)
- Terraform installed
- kubectl installed
- Helm installed
- Git configured with access to this repo

### Phase 1: Destroy (if rebuilding)
cd infra-terraform
terraform destroy

Type "yes" when prompted

### Phase 2: Create Infrastructure
erraform apply

Type "yes" when prompted — creates ~20 resources


### Phase 3: Connect to AKS
az aks get-credentials --name learningsteps-aks --resource-group rg-learningsteps-devops --overwrite-existing


### Phase 4: Enable CSI Driver + Wire Identity
az aks enable-addons --addons azure-keyvault-secrets-provider --name learningsteps-aks --resource-group rg-learningsteps-devops

Get new identity
$objectId = az aks show --name learningsteps-aks --resource-group rg-learningsteps-devops --query "addonProfiles.azureKeyvaultSecretsProvider.identity.objectId" -o tsv
$clientId = az aks show --name learningsteps-aks --resource-group rg-learningsteps-devops --query "addonProfiles.azureKeyvaultSecretsProvider.identity.clientId" -o tsv

Grant Key Vault access
$kvScope = az keyvault show --name kv-learningsteps-mk --query id -o tsv
az role assignment create --assignee $objectId --role "Key Vault Secrets User" --scope $kvScope


### Phase 5: Update Manifests
- Edit `k8s/secretproviderclass.yml`: replace `userAssignedIdentityID` with new `$clientId`
- Update GitHub Secret `ACR_PASSWORD` with new ACR password
- Re-grant SP role assignment (see Lesson 4)

### Phase 6: Deploy to Kubernetes
kubectl create namespace monitoring
kubectl apply -f k8s/


### Phase 7: Seed Secret + Restart
$cs = az keyvault secret show --name pg-connection-string --vault-name kv-learningsteps-mk --query value -o tsv
kubectl create secret generic learningsteps-secrets --from-literal="database-url=$cs" -n learningsteps --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment/learningsteps-api -n learningsteps


### Phase 8: Install Monitoring
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --values k8s/prometheus-values-lean.yml
kubectl apply -f k8s/servicemonitor.yml


### Phase 9: Rebuild Docker Image
git commit --allow-empty -m "Rebuild Docker image after ACR recreation"
git push


### Phase 10: Find New URLs
kubectl get svc -n learningsteps
kubectl get svc -n monitoring monitoring-grafana


---

## What's Automated vs Manual

| Component | Managed By | Rebuild Effort |
|-----------|-----------|---------------|
| Resource Group, VNet, Subnets, NSG | Terraform | Automatic |
| AKS Cluster | Terraform | Automatic |
| ACR | Terraform | Automatic |
| PostgreSQL | Terraform | Automatic |
| Key Vault + Secrets | Terraform | Automatic |
| CSI Driver Identity | Azure CLI | Manual (3 commands) |
| K8s Manifests | kubectl | Manual (1 command) |
| Helm Charts | Helm | Manual (1 command) |
| Docker Image | GitHub Actions | Triggered by empty commit |
| GitHub Secrets | GitHub UI | Manual (1 secret) |
| SP Role Assignment | Azure CLI | Manual (1 command) |

## Design Decision: Why Not Full Automation?

We intentionally chose **not** to have Terraform manage Kubernetes manifests or Helm deployments. This avoids a chicken-and-egg problem: Terraform needs the AKS cluster to exist before it can deploy to it, but a single `terraform apply` creates and deploys in one pass. Keeping infrastructure (Terraform) and application deployment (CI/CD + kubectl) separate is a widely adopted industry pattern.
