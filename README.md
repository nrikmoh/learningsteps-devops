# LearningSteps - DevOps Pipeline on Azure

![CI/CD Pipeline](https://github.com/nrikmoh/learningsteps-devops/actions/workflows/cicd.yml/badge.svg)

A fully automated DevSecOps pipeline for the LearningSteps API, deployed on Microsoft Azure. Every git push to the reference branch automatically builds, security-scans (12 tools), and deploys the application to a live AKS cluster with zero manual intervention. Includes live Prometheus + Grafana monitoring dashboards.

---

## Architecture Overview

The application runs entirely within a private Azure Virtual Network. Users reach the app through a public Load Balancer, which routes traffic to hardened AKS pods. The pods connect to a private PostgreSQL database and retrieve secrets from Azure Key Vault via the CSI Driver. No database or secret is exposed to the internet.

- Internet -> Azure Load Balancer (public IP, port 80)
- Load Balancer -> AKS Pods (port 8000, non-root, read-only filesystem, all capabilities dropped)
- AKS Pods -> PostgreSQL Flexible Server (private, port 5432, DB subnet only)
- AKS Pods -> Azure Key Vault (secrets auto-synced via CSI Driver every 2 minutes)
- Prometheus -> AKS Pods (scrapes /metrics endpoint every 15 seconds)
- Grafana -> Prometheus (visualizes metrics on live dashboards)
- GitHub Actions -> ACR (image push after 12-tool security scan)
- GitHub Actions -> AKS (automated rolling deployment via Service Principal)

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Application | Python 3.12, FastAPI, Uvicorn | REST API backend |
| Containerization | Docker, Azure Container Registry | Image build and storage |
| Infrastructure | Terraform 1.16, Azure RM Provider 4.x | All cloud resources as code |
| CI/CD | GitHub Actions | Automated build, scan, deploy |
| Security | Trivy, tfsec, Checkov, Bandit, Semgrep, Hadolint, pip-audit, Kube-score, TruffleHog, flake8 | 12-tool security scanning |
| Orchestration | Azure Kubernetes Service (AKS) | Container orchestration |
| Database | PostgreSQL 16 Flexible Server | Private relational database |
| Secrets | Azure Key Vault + CSI Driver | Centralized secret management with auto-sync to pods |
| Monitoring | Prometheus, Grafana | Metrics collection and live dashboards |
| Networking | VNet, NSGs, Private DNS, NetworkPolicy | Defense in depth |
| Scaling | Horizontal Pod Autoscaler | Automatic pod scaling (1-5 pods) |
| Dependencies | Dependabot | Automated dependency updates |

---

## Security Scanning (12 Tools)

The CI/CD pipeline runs 12 security checks across every layer of the stack:

| Tool | Scans | Gate |
|------|-------|------|
| Trivy | Docker image OS packages and CVEs | Hard gate (blocks on HIGH/CRITICAL) |
| tfsec | Terraform IaC misconfigurations | Soft fail (reports warnings) |
| Checkov | Terraform + K8s manifests + Dockerfile | Soft fail with documented risk acceptance |
| Bandit | Python source code (SQL injection, hardcoded secrets) | Report only |
| Semgrep | Deep Python code analysis | Report only |
| Hadolint | Dockerfile best practices | Error threshold |
| pip-audit | Python package dependency CVEs | Report only |
| Kube-score | K8s manifest production-readiness | Report only |
| TruffleHog | Git history and code for leaked secrets | Hard gate (verified secrets only) |
| flake8 | Python code style and quality | Report only |
| terraform fmt | Terraform code formatting | Hard gate |
| terraform validate | Terraform syntax correctness | Hard gate |

Additionally, pytest runs automated tests (when a tests/ directory exists). All Checkov findings have been evaluated and documented in .checkov.yml with risk acceptance rationale.

---

## Security Hardening

| Feature | Implementation |
|---------|---------------|
| Non-root containers | UID 10001, runAsNonRoot enforced at pod level |
| Read-only filesystem | readOnlyRootFilesystem: true |
| No privilege escalation | allowPrivilegeEscalation: false |
| All capabilities dropped | capabilities.drop: ALL (including NET_RAW) |
| Seccomp profile | RuntimeDefault |
| No service account token | automountServiceAccountToken: false |
| Private database | No public endpoint, VNet delegation, NSG rules |
| Network Security Groups | AKS allows 80/443; DB allows 5432 from AKS subnet only |
| Kubernetes NetworkPolicy | Pods can only reach DB subnet (5432) and DNS (53) |
| Least-privilege RBAC | AKS has AcrPull and KV Secrets User roles only |
| Secret management | DB credentials in Key Vault with expiration, auto-synced to pods via CSI Driver |
| Application metrics | Prometheus scrapes /metrics endpoint, Grafana dashboards |
| Container scanning | Trivy blocks on fixable HIGH/CRITICAL CVEs |
| Secret scanning | TruffleHog scans git history for leaked credentials |
| IaC scanning | tfsec + Checkov with documented risk acceptance |
| Code scanning | Bandit + Semgrep + flake8 for Python vulnerabilities and quality |
| GitHub token lockdown | Pipeline token restricted to contents: read |
| Dependency monitoring | Dependabot for Docker, pip, and Actions |
| Image traceability | Deployments use commit SHA tags |
| HEALTHCHECK | Docker HEALTHCHECK instruction included |
| Rolling updates | maxSurge: 1, maxUnavailable: 0 (zero downtime) |
| Pod Disruption Budget | minAvailable: 1 during maintenance |

---

## Project Structure

- api/ - FastAPI application source code
- Dockerfile - Non-root, Debian 12 stable, HEALTHCHECK, apt-upgraded
- .dockerignore - Excludes .git, terraform state from image
- .gitignore - Excludes Python cache, IDE files, OS files
- .checkov.yml - Checkov risk acceptance documentation
- infra-terraform/ - Infrastructure as Code (main.tf, variables.tf, outputs.tf)
- k8s/ - Kubernetes manifests (namespace, deployment, service, configmap, HPA, PDB, networkpolicy)
- k8s/secretproviderclass.yml - Key Vault CSI Driver configuration
- k8s/servicemonitor.yml - Prometheus ServiceMonitor for app metrics
- k8s/prometheus-values-lean.yml - Helm values for monitoring stack
- .github/workflows/cicd.yml - Full CI/CD pipeline (build, 12-tool scan, deploy)
- .github/dependabot.yml - Automated dependency update PRs
- README.md - This file

---

## CI/CD Pipeline

The pipeline runs on every push to the reference branch with two jobs:

**Job 1: build-and-scan**
1. Checkout code (full history for TruffleHog)
2. TruffleHog secret scan (git history, verified secrets only)
3. flake8 lint + pytest (Python quality and tests)
4. Build Docker image (Debian 12, non-root, apt-upgraded)
5. Hadolint scan (Dockerfile)
6. Trivy scan (image CVEs, hard gate)
7. Bandit scan (Python code)
8. pip-audit scan (Python deps)
9. Semgrep scan (deep code analysis)
10. Terraform fmt + validate
11. tfsec scan (IaC)
12. Checkov scan (IaC + K8s + Dockerfile)
13. Kube-score scan (K8s manifests)
14. Push image to ACR with commit SHA tag

**Job 2: deploy (only if Job 1 passes)**
1. Azure Login via Service Principal
2. Connect to AKS
3. Apply all K8s manifests with rolling update
4. Replace image tag with exact commit SHA

---

## Infrastructure (Terraform)

| Resource | Name | Details |
|----------|------|---------|
| Resource Group | rg-learningsteps-devops | westeurope |
| Virtual Network | learningsteps-vnet | 10.0.0.0/16 |
| AKS Subnet | aks-subnet | 10.0.1.0/24 |
| DB Subnet | db-subnet | 10.0.2.0/24 (delegated) |
| AKS Cluster | learningsteps-aks | 1x D2s_v6, K8s 1.36, auto-upgrade, Azure Policy |
| ACR | nrikmohacr | Basic tier |
| PostgreSQL | learningsteps-db-mk | B1ms, v16, private, 32GB |
| Key Vault | kv-learningsteps-mk | Standard, RBAC, secrets with expiration |
| Private DNS | private.postgres.database.azure.com | Linked to VNet |
| NSG (AKS) | aks-nsg | Allow 80, 443 inbound |
| NSG (DB) | db-nsg | Allow 5432 from 10.0.1.0/24 only |
| Monitoring | Prometheus + Grafana (Helm) | Deployed via kube-prometheus-stack |

All Terraform resources tagged: project=learningsteps, environment=dev, managed_by=terraform.

---

## Live Endpoints

| Service | URL |
|---------|-----|
| API (Swagger) | http://20.4.140.251/docs |
| API Metrics | http://20.4.140.251/metrics |
| Grafana | http://20.4.154.214 |

---

## Quick Start

Prerequisites: Azure CLI, Terraform v1.5+, Docker Desktop, kubectl, Helm, Azure subscription.

    az login
    cd infra-terraform
    terraform init
    terraform apply
    az aks get-credentials --name learningsteps-aks --resource-group rg-learningsteps-devops
    kubectl apply -f k8s/
    helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --values k8s/prometheus-values-lean.yml

---

## Cost Estimate

| Resource | Tier | Monthly |
|----------|------|---------|
| AKS (1x D2s_v6) | Standard | $60-75 |
| PostgreSQL | B1ms | $13-18 |
| ACR | Basic | $5 |
| Key Vault | Standard | $1-3 |
| Load Balancer + IP | Basic | $3 |
| Prometheus + Grafana | On existing AKS node | Free |
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
| 2 | IaC: AKS, PostgreSQL, Key Vault, NSGs, Private DNS, RBAC | Done |
| 3 | CI/CD + DevSecOps: GitHub Actions, 12-tool security scanning | Done |
| 4 | K8s hardening, CSI Driver secret sync, Prometheus + Grafana monitoring, secret scanning, linting | Done |

---

## Key Lessons Learned

1. Infrastructure as Code is non-negotiable. Manual portal clicks are not reproducible.
2. Security scanning must block the pipeline, not just warn. A warning nobody reads is useless.
3. Private networking by default. Databases should never have public IPs.
4. Least privilege everywhere. AKS gets AcrPull, not Owner. Pipeline token gets read, not write.
5. Secrets belong in a vault with expiration dates, never in code or config files.
6. Containers should never run as root, should drop all capabilities, and use read-only filesystems.
7. ignore-unfixed is a real-world necessity for OS-level CVEs without patches.
8. Rolling updates with maxUnavailable 0 means zero-downtime deployments.
9. Every skipped security check must be documented with a rationale. Risk acceptance is not the same as ignorance.
10. Defense in depth: NSGs + NetworkPolicy + RBAC + private endpoints + secret management. No single layer is enough.
11. CSI Driver eliminates manual secret injection. Key Vault becomes the single source of truth, auto-synced to pods every 2 minutes.
12. Monitoring is not optional. If you cannot see your metrics, you cannot fix your problems. Prometheus + Grafana turns invisible infrastructure into visible dashboards.

---

*Built as a hands-on DevSecOps learning project by [Moh](https://github.com/nrikmoh). Four weeks from zero cloud experience to a production-grade automated pipeline on Azure with 12-tool security scanning, Key Vault CSI Driver integration, and live Prometheus + Grafana monitoring.*
