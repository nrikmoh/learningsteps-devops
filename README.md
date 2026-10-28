# LearningSteps - DevOps Pipeline on Azure

![CI/CD Pipeline](https://github.com/nrikmoh/learningsteps-devops/actions/workflows/cicd.yml/badge.svg)

A fully automated DevSecOps pipeline for the LearningSteps API, deployed on Microsoft Azure. Every git push to the reference branch automatically builds, security-scans, and deploys the application to a live AKS cluster with zero manual intervention.

---

## Architecture Overview

The application runs entirely within a private Azure Virtual Network. Users reach the app through a public Load Balancer, which routes traffic to AKS pods. The pods connect to a private PostgreSQL database and retrieve secrets from Azure Key Vault. No database or secret is exposed to the internet.

- Internet -> Azure Load Balancer (public IP, port 80)
- Load Balancer -> AKS Pods (port 8000, non-root containers)
- AKS Pods -> PostgreSQL Flexible Server (private, port 5432, DB subnet only)
- AKS Pods -> Azure Key Vault (secrets retrieval via RBAC)
- GitHub Actions -> ACR (image push after security scan)
- GitHub Actions -> AKS (automated deployment via Service Principal)

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Application | Python 3.12, FastAPI, Uvicorn | REST API backend |
| Containerization | Docker, Azure Container Registry | Image build and storage |
| Infrastructure | Terraform 1.16, Azure RM Provider 4.x | All cloud resources as code |
| CI/CD | GitHub Actions | Automated build, scan, deploy |
| Security | Trivy, tfsec | Container and IaC vulnerability scanning |
| Orchestration | Azure Kubernetes Service (AKS) | Container orchestration |
| Database | PostgreSQL 16 Flexible Server | Private relational database |
| Secrets | Azure Key Vault | Centralized secret management |
| Networking | VNet, NSGs, Private DNS, NetworkPolicy | Defense in depth |
| Scaling | Horizontal Pod Autoscaler | Automatic pod scaling |
| Dependencies | Dependabot | Automated dependency updates |

---

## Project Structure

- api/ - FastAPI application source code
- Dockerfile - Non-root, Debian 12 stable container
- .dockerignore - Excludes .git, terraform state from image
- .gitignore - Excludes Python cache, IDE files, OS files
- infra-terraform/ - Infrastructure as Code (main.tf, variables.tf, outputs.tf)
- k8s/ - Kubernetes manifests (deployment, service, HPA, PDB, networkpolicy)
- .github/workflows/cicd.yml - Full CI/CD pipeline
- .github/dependabot.yml - Automated dependency update PRs
- README.md - This file

---

## CI/CD Pipeline Details

The pipeline runs on every push to the reference branch and consists of two jobs:

**Job 1: build-and-scan**

1. Checkout code from GitHub
2. Build Docker image (Debian 12 stable, non-root user, apt-upgraded)
3. Trivy scan: blocks on fixable HIGH/CRITICAL vulnerabilities
4. Terraform fmt check: ensures consistent code formatting
5. Terraform validate: ensures syntactic correctness
6. tfsec scan: checks for IaC security misconfigurations
7. Login to ACR using encrypted GitHub Secrets
8. Tag image with commit SHA + latest, push to ACR

**Job 2: deploy (only runs if Job 1 passes)**

1. Checkout code
2. Authenticate to Azure via Service Principal
3. Connect to AKS cluster
4. Apply all Kubernetes manifests with rolling update strategy
5. Replace image tag with exact commit SHA for full traceability

---

## Security Features

| Feature | Implementation |
|---------|---------------|
| Non-root containers | Dockerfile creates appuser (UID 1000), runs as non-root |
| Private database | PostgreSQL has no public endpoint, DB subnet only |
| Network Security Groups | AKS allows 80/443; DB allows 5432 from AKS subnet only |
| Kubernetes NetworkPolicy | Pods can only reach DB subnet (5432) and DNS (53) |
| Least-privilege RBAC | AKS has AcrPull and KV Secrets User roles only |
| Secret management | DB credentials in Key Vault, injected as K8s Secrets |
| Container scanning | Trivy blocks on fixable HIGH/CRITICAL CVEs |
| IaC scanning | tfsec checks Terraform for misconfigurations |
| GitHub token lockdown | Pipeline token restricted to contents: read |
| Dependency monitoring | Dependabot opens PRs for Docker, pip, and Actions |
| Image traceability | Deployments use commit SHA tags, not latest |
| .dockerignore | Prevents .git and terraform state from entering images |

---

## Infrastructure (Terraform)

| Resource | Name | Details |
|----------|------|---------|
| Resource Group | rg-learningsteps-devops | westeurope |
| Virtual Network | learningsteps-vnet | 10.0.0.0/16 |
| AKS Subnet | aks-subnet | 10.0.1.0/24 |
| DB Subnet | db-subnet | 10.0.2.0/24 (delegated) |
| AKS Cluster | learningsteps-aks | 1x D2s_v6, K8s 1.36 |
| ACR | nrikmohacr | Basic tier |
| PostgreSQL | learningsteps-db-mk | B1ms, v16, private, 32GB |
| Key Vault | kv-learningsteps-mk | Standard, RBAC |
| Private DNS | private.postgres.database.azure.com | Linked to VNet |
| NSG (AKS) | aks-nsg | Allow 80, 443 inbound |
| NSG (DB) | db-nsg | Allow 5432 from 10.0.1.0/24 only |

All resources tagged: project=learningsteps, environment=dev, managed_by=terraform.

---

## Quick Start

Prerequisites: Azure CLI, Terraform v1.5+, Docker Desktop, kubectl, Azure subscription.

    az login
    cd infra-terraform
    terraform init
    terraform apply
    az aks get-credentials --name learningsteps-aks --resource-group rg-learningsteps-devops
    kubectl apply -f k8s/

---

## Cost Estimate

| Resource | Tier | Monthly |
|----------|------|---------|
| AKS (1x D2s_v6) | Standard | $60-75 |
| PostgreSQL | B1ms | $13-18 |
| ACR | Basic | $5 |
| Key Vault | Standard | $1-3 |
| Load Balancer + IP | Basic | $3 |
| VNet, DNS, NSGs | - | Free |
| **Total** | | **$82-104** |

Auto-stop policy shuts down AKS at midnight UTC. Run az aks start each morning.

---

## Cleanup

    cd infra-terraform
    terraform destroy

---

## Progress Log

| Week | Milestone | Status |
|------|-----------|--------|
| 1 | Containerization: Dockerfile, ACR push, GitHub repo | Done |
| 2 | IaC: AKS, PostgreSQL, Key Vault, NSGs, Private DNS | Done |
| 3 | CI/CD + DevSecOps: GitHub Actions, Trivy, tfsec | Done |
| 4 | K8s: HPA, PDB, NetworkPolicy, automated deploy | Done |

---

## Key Lessons Learned

1. Infrastructure as Code is non-negotiable. Manual portal clicks are not reproducible.
2. Security scanning must block the pipeline, not just warn.
3. Private networking by default. Databases should never have public IPs.
4. Least privilege everywhere. AKS gets AcrPull, not Owner.
5. Secrets belong in a vault, never in code or config files.
6. Containers should never run as root. One Dockerfile line eliminates an attack vector.
7. ignore-unfixed is a real-world necessity for OS-level CVEs.
8. Rolling updates with maxUnavailable 0 means zero-downtime deployments.

---

*Built as a hands-on DevSecOps learning project by [Moh](https://github.com/nrikmoh). Four weeks from zero cloud experience to a production-grade automated pipeline on Azure.*
