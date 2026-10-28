# LearningSteps - DevOps Pipeline on Azure

A fully automated DevOps pipeline for the LearningSteps API, deployed on Microsoft Azure using Infrastructure as Code, CI/CD, container security scanning, and Kubernetes orchestration.

**Goal:** Every git push to the reference branch automatically builds, scans, and deploys the application to a live AKS cluster with zero manual intervention.

---

## Architecture

Internet -> AKS NSG (Allow 80, 443) -> Azure VNet (10.0.0.0/16) -> AKS Subnet (10.0.1.0/24) with AKS Pods -> DB Subnet (10.0.2.0/24) with PostgreSQL Flexible Server. ACR and Key Vault sit outside the VNet.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Application | Python 3.12, FastAPI, Uvicorn |
| Containerization | Docker, Azure Container Registry (ACR) |
| Infrastructure | Terraform (HCL), Azure (AKS, VNet, PostgreSQL, Key Vault) |
| CI/CD | GitHub Actions |
| Security | Trivy (container scanning), tfsec (IaC scanning) |
| Orchestration | Azure Kubernetes Service (AKS) |
| Monitoring | Prometheus + Grafana (planned) |

---

## Project Structure

- api/ — FastAPI application source code
- Dockerfile — Container build
- infra-terraform/ — Infrastructure as Code (main.tf, variables.tf, outputs.tf)
- .github/workflows/ — CI/CD pipeline (Week 3)
- README.md — This file

---

## Quick Start

### Prerequisites

- Azure CLI (az)
- Terraform v1.5+
- Docker Desktop
- kubectl
- An Azure subscription

### 1. Authenticate with Azure

    az login

### 2. Deploy Infrastructure

    cd infra-terraform
    terraform init
    terraform apply

### 3. Connect to AKS

    az aks get-credentials --name learningsteps-aks --resource-group rg-learningsteps-devops
    kubectl get nodes

---

## Cost Estimate

| Resource | Tier | Monthly Cost |
|----------|------|-------------|
| AKS (1x D2s_v6 node) | Standard | ~$60-75 |
| PostgreSQL Flexible Server | B1ms Burstable | ~$13-18 |
| Azure Container Registry | Basic | ~$5 |
| Key Vault | Standard | ~$1-3 |
| VNet + DNS + NSGs | - | Free |
| **Total** | | **~$80-100** |

Resources are subject to an auto-stop policy (midnight UTC daily). Run `az aks start --name learningsteps-aks --resource-group rg-learningsteps-devops` each morning.

---

## Cleanup

To destroy all resources and stop billing:

    cd infra-terraform
    terraform destroy

---

## Progress Log

| Week | Milestone | Status |
|------|-----------|--------|
| 1 | Containerization: Dockerfile, ACR push, GitHub repo | Done |
| 2 | IaC: AKS, PostgreSQL, Key Vault, NSGs, Private DNS | Done |
| 3 | CI/CD + DevSecOps: GitHub Actions, Trivy, tfsec | Planned |
| 4 | Orchestration: K8s manifests, deploy, monitoring | Planned |

---

## Security Features

- **Private networking:** PostgreSQL has no public endpoint; accessible only from the AKS subnet via NSG rules
- **Least-privilege RBAC:** AKS can pull images (AcrPull) and read secrets (KV Secrets User) only
- **Automated scanning:** CI/CD pipeline blocks deployment on high/critical vulnerabilities (Week 3)
- **Secrets management:** Database credentials stored in Azure Key Vault, never in code

---

*Built as a hands-on DevOps learning project by [Moh](https://github.com/nrikmoh).*