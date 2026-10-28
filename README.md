LearningSteps - DevOps Pipeline on Azure
CI/CD Pipeline

A fully automated DevSecOps pipeline for the LearningSteps API, deployed on Microsoft Azure. Every git push to the reference branch automatically builds, security-scans, and deploys the application to a live AKS cluster with zero manual intervention.

Architecture Overview
The application runs entirely within a private Azure Virtual Network. Users reach the app through a public Load Balancer, which routes traffic to AKS pods. The pods connect to a private PostgreSQL database and retrieve secrets from Azure Key Vault. No database or secret is exposed to the internet.

Components:

Internet -> Azure Load Balancer (public IP, port 80)
Load Balancer -> AKS Pods (port 8000, non-root containers)
AKS Pods -> PostgreSQL Flexible Server (private, port 5432, DB subnet only)
AKS Pods -> Azure Key Vault (secrets retrieval via RBAC)
GitHub Actions -> ACR (image push after security scan)
GitHub Actions -> AKS (automated deployment via Service Principal)
Tech Stack
Layer	Technology	Purpose
Application	Python 3.12, FastAPI, Uvicorn	REST API backend
Containerization	Docker, Azure Container Registry	Image build and storage
Infrastructure	Terraform 1.16, Azure RM Provider 4.x	All cloud resources as code
CI/CD	GitHub Actions	Automated build, scan, deploy
Security	Trivy, tfsec	Container and IaC vulnerability scanning
Orchestration	Azure Kubernetes Service (AKS)	Container orchestration
Database	PostgreSQL 16 Flexible Server	Private relational database
Secrets	Azure Key Vault	Centralized secret management
Networking	VNet, NSGs, Private DNS, NetworkPolicy	Defense in depth
Scaling	Horizontal Pod Autoscaler	Automatic pod scaling
Dependencies	Dependabot	Automated dependency updates

Project Structure

learningsteps/
+-- api/                        # FastAPI application source code
+-- Dockerfile                  # Non-root, Debian 12 stable container
+-- .dockerignore               # Excludes .git, terraform state from image
+-- .gitignore                  # Excludes Python cache, IDE files, OS files
+-- infra-terraform/            # Infrastructure as Code
|   +-- main.tf                 # 15+ Azure resource definitions
|   +-- variables.tf            # All configurable parameters
|   +-- outputs.tf              # Useful output values (FQDNs, URIs)
|   +-- .gitignore              # Excludes state files and provider binaries
+-- k8s/                        # Kubernetes manifests
|   +-- namespace.yml           # Dedicated namespace isolation
|   +-- deployment.yml          # App deployment with probes and rolling updates
|   +-- service.yml             # LoadBalancer service (public IP)
|   +-- configmap.yml           # Non-secret app configuration
|   +-- hpa.yml                 # Horizontal Pod Autoscaler (1-5 pods)
|   +-- pdb.yml                 # Pod Disruption Budget (min 1 available)
|   +-- networkpolicy.yml       # Network firewall rules
+-- .github/
|   +-- workflows/
|   |   +-- cicd.yml            # Full CI/CD pipeline (build, scan, deploy)
|   +-- dependabot.yml          # Automated dependency update PRs
+-- README.md                   # This file


CI/CD Pipeline Details
The pipeline runs on every push to the reference branch and consists of two jobs:

Job 1: build-and-scan
Checkout code from GitHub
Build Docker image (Debian 12 stable, non-root user, apt-upgraded)
Trivy scan: blocks on fixable HIGH/CRITICAL vulnerabilities
Terraform fmt check: ensures consistent code formatting
Terraform validate: ensures syntactic correctness
tfsec scan: checks for IaC security misconfigurations (soft fail for dev)
Login to ACR using encrypted GitHub Secrets
Tag image with commit SHA + latest, push to ACR
Job 2: deploy (only runs if Job 1 passes)
Checkout code
Authenticate to Azure via Service Principal
Connect to AKS cluster
Apply all Kubernetes manifests with rolling update strategy
Replace image tag with exact commit SHA for full traceability
Security Features
Feature	Implementation
Non-root containers	Dockerfile creates appuser (UID 1000), runs as non-root
Private database	PostgreSQL has no public endpoint, accessible only from DB subnet
Network Security Groups	AKS NSG allows 80/443 only; DB NSG allows 5432 from AKS subnet only
Kubernetes NetworkPolicy	Pods can only reach DB subnet (5432) and DNS (53)
Least-privilege RBAC	AKS has AcrPull and KV Secrets User roles only
Secret management	DB credentials in Azure Key Vault, injected as K8s Secrets
Container scanning	Trivy blocks deployment on fixable HIGH/CRITICAL CVEs
IaC scanning	tfsec checks Terraform for misconfigurations
GitHub token lockdown	Pipeline token restricted to contents: read
Dependency monitoring	Dependabot opens PRs for Docker, pip, and Actions updates
Image traceability	Deployments use commit SHA tags, not :latest
.dockerignore	Prevents .git history and terraform state from entering images
.gitignore	Prevents secrets, state files, and binaries from reaching GitHub
Infrastructure Details (Terraform)
Resource	Name	Details
Resource Group	rg-learningsteps-devops	westeurope
Virtual Network	learningsteps-vnet	10.0.0.0/16
AKS Subnet	aks-subnet	10.0.1.0/24
DB Subnet	db-subnet	10.0.2.0/24 (delegated)
AKS Cluster	learningsteps-aks	1x Standard_D2s_v6, Kubernetes 1.36
ACR	nrikmohacr	Basic tier
PostgreSQL	learningsteps-db-mk	B1ms, v16, private, 32GB
Key Vault	kv-learningsteps-mk	Standard, RBAC, purge disabled
Private DNS	private.postgres.database.azure.com	Linked to VNet
NSG (AKS)	aks-nsg	Allow 80, 443 inbound
NSG (DB)	db-nsg	Allow 5432 from 10.0.1.0/24, deny all else
All resources are tagged with: project=learningsteps, environment=dev, managed_by=terraform.

Quick Start
Prerequisites
Azure CLI (az)
Terraform v1.5+
Docker Desktop
kubectl
An Azure subscription
1. Authenticate with Azure
text

az login
2. Deploy Infrastructure
text

cd infra-terraform
terraform init
terraform apply
3. Connect to AKS
text

az aks get-credentials --name learningsteps-aks --resource-group rg-learningsteps-devops
4. Create Kubernetes Secret
text

$connStr = az keyvault secret show --vault-name kv-learningsteps-mk --name pg-connection-string --query "value" --output tsv
kubectl create secret generic learningsteps-secrets --namespace learningsteps --from-literal=DATABASE_URL=$connStr
5. Deploy Application
text

kubectl apply -f k8s/
6. Access the App
text

kubectl get service learningsteps-service -n learningsteps
(visit the EXTERNAL-IP in your browser)
Cost Estimate
Resource	Tier	Monthly Cost
AKS (1x D2s_v6)	Standard	~$60-75
PostgreSQL Flexible Server	B1ms Burstable	~$13-18
Azure Container Registry	Basic	~$5
Key Vault	Standard	~$1-3
Load Balancer + Public IP	Basic	~$3
VNet, DNS, NSGs	-	Free
Total		~$82-104
Note: An auto-stop policy shuts down AKS daily at midnight UTC to save costs. Run az aks start --name learningsteps-aks --resource-group rg-learningsteps-devops each morning.

Cleanup
To destroy all resources and stop all billing:

text

cd infra-terraform
terraform destroy
Progress Log
Week	Milestone	Status
1	Containerization: Dockerfile, ACR push, GitHub repo	Done
2	IaC: AKS, PostgreSQL, Key Vault, NSGs, Private DNS, RBAC	Done
3	CI/CD + DevSecOps: GitHub Actions, Trivy, tfsec, Dependabot	Done
4	Orchestration: K8s manifests, HPA, PDB, NetworkPolicy, automated deploy	Done
Key Lessons Learned
Infrastructure as Code is non-negotiable. Manually clicking in a portal is not reproducible and not auditable.
Security scanning must block the pipeline, not just warn. A warning that nobody reads is useless.
Private networking by default. The database should never have a public IP unless absolutely required.
Least privilege everywhere. AKS gets AcrPull, not Owner. The pipeline token gets read, not write.
Secrets belong in a vault, not in code, not in environment files, not in chat messages.
Containers should never run as root. One line in the Dockerfile eliminates an entire attack vector.
ignore-unfixed is a real-world necessity. Blocking on vulnerabilities that the OS vendor has not patched yet means your pipeline is permanently broken.
Rolling updates with maxUnavailable: 0 means zero-downtime deployments. Users never see an error during updates.
Built as a hands-on DevSecOps learning project by Moh. Four weeks from zero cloud experience to a production-grade automated pipeline on Azure.


