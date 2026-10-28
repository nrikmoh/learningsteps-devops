# DevSecOps Pipeline on Azure: A Four-Week Journey from Zero to Production

**Author:** Moh (nrikmoh)
**Date:** October 2026
**Repository:** https://github.com/nrikmoh/learningsteps-devops
**Live Application:** http://20.4.140.251/docs

---

## Executive Summary

This report documents the design, implementation, and hardening of a fully automated DevSecOps pipeline for the LearningSteps API on Microsoft Azure. Over four weeks, the project evolved from a manual VM-based deployment to a production-grade Kubernetes infrastructure with 10-tool security scanning, zero-downtime deployments, and Infrastructure as Code reproducibility. Every git push to the repository now triggers an automated pipeline that builds, scans, and deploys the application without human intervention.

The project demonstrates proficiency in containerization (Docker, ACR), Infrastructure as Code (Terraform), CI/CD (GitHub Actions), security scanning (Trivy, tfsec, Checkov, Bandit, Semgrep, Hadolint, pip-audit, Kube-score), Kubernetes orchestration (AKS), and cloud networking (VNet, NSGs, Private DNS, NetworkPolicy).

---

## 1. Background and Objectives

### 1.1 The Application

LearningSteps is a Python-based REST API built with FastAPI. It provides endpoints for managing learning steps and user progress. The source code is maintained at https://github.com/CyberstepsDE/learningsteps (reference branch).

### 1.2 The Challenge

The objective was to deploy this application on Azure with a fully automated, secure, and reproducible pipeline within four weeks. The five pillars of the project were:

1. **Containerization:** Package the application in a Docker container and store it in a private registry.
2. **Infrastructure as Code:** Define all cloud resources in Terraform so the entire environment can be recreated with a single command.
3. **DevSecOps:** Integrate security scanning into the CI/CD pipeline so vulnerabilities are caught before deployment.
4. **CI/CD:** Automate the build-scan-deploy cycle on every git push using GitHub Actions.
5. **Orchestration:** Deploy to Azure Kubernetes Service (AKS) with auto-scaling, health monitoring, and zero-downtime updates.

### 1.3 Constraints

- Azure subscription with auto-stop policy (resources shut down at midnight UTC daily).
- Limited vCPU quota in the westeurope region.
- Budget-conscious: target under $100/month.
- All infrastructure must be reproducible via terraform destroy + terraform apply.

---

## 2. Pre-Project: Lessons from a Failed First Attempt

Before the four-week project began, an initial deployment was attempted using manual Azure CLI commands and a virtual machine. This approach encountered numerous issues:

- **Region restrictions:** The germanywestcentral region blocked PostgreSQL Flexible Server creation. All resources had to be migrated to westeurope.
- **NSG region mismatch:** Network Security Groups created without an explicit location defaulted to the wrong region, causing InvalidResourceReference errors.
- **Private DNS naming:** Azure rejected multiple naming formats for the PostgreSQL private DNS zone. The solution required pre-creating the DNS zone and passing its full ARM resource ID.
- **Port 80 permission denied:** Linux restricts ports below 1024 to root. The application was reconfigured to use port 8000.
- **Database auto-stop:** The burstable B1ms PostgreSQL tier auto-stopped after inactivity, causing connection timeouts.

**Key takeaway:** Manual deployments are fragile, error-prone, and impossible to reproduce. This failure motivated the shift to Infrastructure as Code for the main project. The entire manual infrastructure was destroyed with az group delete and rebuilt from scratch using Terraform.

---

## 3. Week 1: Containerization

### 3.1 What Was Done

- Installed Docker Desktop (v29.9.2, amd64) and Git for Windows (v2.56.0).
- Cloned the LearningSteps repository (reference branch).
- Created a Dockerfile based on python:3.12-slim.
- Built and tested the Docker image locally.
- Created an Azure Container Registry (nrikmohacr, Basic tier, westeurope).
- Pushed the Docker image to ACR.
- Created a new GitHub repository (nrikmoh/learningsteps-devops) and pushed the code.

### 3.2 Challenges and Solutions

**Challenge 1: Missing DATABASE_URL**
The application crashed on startup with ValueError: DATABASE_URL environment variable is missing. The app checks for a database connection string at startup, even during local testing.
*Solution:* Passed a dummy DATABASE_URL via docker run -e for local testing. The real connection string would be injected later via Kubernetes Secrets.

**Challenge 2: PYTHONPATH misconfiguration**
The application threw ModuleNotFoundError because the repositories/ directory is nested inside api/. Python could not find the modules.
*Solution:* Added ENV PYTHONPATH=.:./api to the Dockerfile, telling Python to search both the root and the api/ directory.

**Challenge 3: Port 80 permission denied**
Binding to port 80 inside the container failed with Errno 13 because Linux restricts privileged ports (below 1024) to the root user.
*Solution:* Changed the application to listen on port 8000 and updated the Dockerfile EXPOSE directive accordingly.

### 3.3 Deliverables

- Dockerfile (later hardened in Week 3 with non-root user, Debian 12, HEALTHCHECK).
- Docker image pushed to nrikmohacr.azurecr.io/learningsteps-api:latest.
- GitHub repository initialized with the application code.

---

## 4. Week 2: Infrastructure as Code with Terraform

### 4.1 What Was Done

- Installed Terraform v1.16.6 via winget.
- Wrote main.tf to define all Azure resources: Resource Group, Virtual Network, AKS and DB subnets, AKS cluster, PostgreSQL Flexible Server, Key Vault, Private DNS Zone, ACR role assignment, and NSGs.
- Created variables.tf to externalize all configurable parameters (region, VM size, subnet prefixes, etc.).
- Created outputs.tf to display useful information after deployment (AKS FQDN, database hostname, Key Vault URI).
- Added resource tags to all resources for cost tracking and organization.
- Imported the existing Resource Group into Terraform state.

### 4.2 Challenges and Solutions

**Challenge 1: Missing subscription registration**
Terraform failed with MissingSubscriptionRegistration for Microsoft.ContainerRegistry and Microsoft.ContainerService. The subscription had not registered these resource providers.
*Solution:* Ran az provider register --namespace Microsoft.ContainerService and waited for registration to complete. Also added resource_provider_registrations = "none" to the Terraform provider block to prevent it from attempting to auto-register dozens of unrelated providers.

**Challenge 2: Kubernetes version not supported**
Terraform attempted to create an AKS cluster with Kubernetes 1.31, which Azure flagged as LTS-only (Long-Term Support, a paid tier).
*Solution:* Removed the kubernetes_version field entirely, allowing Azure to select the latest non-LTS version automatically (1.36.4).

**Challenge 3: Service CIDR overlap**
Azure rejected the AKS cluster because the default service CIDR (10.0.0.0/16) overlapped with the VNet address space.
*Solution:* Explicitly set service_cidr = "172.16.0.0/16" and dns_service_ip = "172.16.0.10" in the network_profile block, using a non-overlapping private range.

**Challenge 4: vCPU quota exhaustion**
The subscription had zero remaining vCPU quota for the Standard_B2s VM family in westeurope.
*Solution:* Wrote a PowerShell script (try-sizes.ps1) that iterated through 8 VM sizes, editing main.tf and running terraform apply for each until one succeeded. Standard_D2s_v6 was the first available size.

**Challenge 5: PostgreSQL zone conflict**
Terraform attempted to modify the availability zone that Azure had automatically assigned to the PostgreSQL server, causing a zone exchange error.
*Solution:* Added lifecycle { ignore_changes = [zone, high_availability] } to the PostgreSQL resource, telling Terraform to accept Azure automatic zone assignment.

**Challenge 6: 238 MB binary pushed to GitHub**
The initial git push included the .terraform/ directory containing 238 MB of provider binaries, exceeding GitHub 100 MB file limit.
*Solution:* Created a .gitignore file excluding .terraform/, *.tfstate, and *.tfstate.backup. Used git reset --soft HEAD~2 to erase the large files from git history, then re-committed cleanly.

### 4.3 Deliverables

- 15+ Azure resources defined in Terraform (reproducible with terraform apply).
- Three-file structure: main.tf, variables.tf, outputs.tf.
- Network Security Groups for AKS (allow 80/443) and DB (allow 5432 from AKS subnet only).
- All resources tagged with project, environment, and managed_by.
- Clean git history with proper .gitignore.

---

## 5. Week 3: CI/CD Pipeline and DevSecOps

### 5.1 What Was Done

- Created a GitHub Actions workflow (.github/workflows/cicd.yml) triggered on every push to the reference branch.
- Configured the pipeline with two jobs: build-and-scan and deploy.
- Integrated 10 security scanning tools across every layer of the stack.
- Added GitHub Secrets for ACR credentials and Azure Service Principal.
- Configured Dependabot for automated dependency updates (Docker, pip, GitHub Actions).
- Hardened the Dockerfile with non-root user, Debian 12 stable base, and HEALTHCHECK.
- Added least-privilege permissions to the GitHub Actions token.

### 5.2 The 10-Tool Security Stack

| Tool | Layer Scanned | Gate Type |
|------|--------------|-----------|
| Trivy | Docker image OS packages and CVEs | Hard gate (blocks on HIGH/CRITICAL) |
| tfsec | Terraform IaC misconfigurations | Soft fail |
| Checkov | Terraform + K8s + Dockerfile | Soft fail with documented risk acceptance |
| Bandit | Python source code | Report only |
| Semgrep | Deep Python code analysis | Report only |
| Hadolint | Dockerfile best practices | Error threshold |
| pip-audit | Python package dependencies | Report only |
| Kube-score | K8s manifest readiness | Report only |
| terraform fmt | Terraform formatting | Hard gate |
| terraform validate | Terraform syntax | Hard gate |

### 5.3 Challenges and Solutions

**Challenge 1: Trivy found 44 HIGH vulnerabilities**
The initial Trivy scan blocked the pipeline with 44 HIGH vulnerabilities, all in OS packages from Debian 13 (trixie), the testing release. None had available patches.
*Solution:* Three changes: (1) switched the base image to python:3.12-slim-bookworm (Debian 12 stable), (2) added apt-get update && apt-get upgrade to the Dockerfile, (3) added ignore-unfixed: true to the Trivy step. The ignore-unfixed flag is an industry-standard practice that prevents the pipeline from blocking on vulnerabilities the OS vendor has not yet patched.

**Challenge 2: tfsec action crashed with jq error**
The tfsec GitHub Action failed with "jq: error: Cannot iterate over null" because it hit GitHub API rate limits when downloading the latest tfsec binary.
*Solution:* Added github_token: ${{ secrets.GITHUB_TOKEN }} to the tfsec action configuration, providing authenticated API access.

**Challenge 3: Trivy action version 0.28.0 not found**
Attempted to pin the Trivy action to version 0.28.0 for reproducibility, but that tag did not exist in the repository.
*Solution:* Reverted to @master with a TODO comment to pin to a release SHA for production use. This highlights the trade-off between stability and maintenance burden in CI/CD pipelines.

**Challenge 4: ACR admin credentials disabled**
The az acr credential show command failed because admin access was disabled by default on the ACR.
*Solution:* Ran az acr update --name nrikmohacr --admin-enabled true. The credentials were stored as encrypted GitHub Secrets (ACR_USERNAME, ACR_PASSWORD), never in code.

### 5.4 Dockerfile Hardening

The Dockerfile evolved significantly during Week 3:

| Feature | Before | After |
|---------|--------|-------|
| Base image | python:3.12-slim (Debian 13) | python:3.12-slim-bookworm (Debian 12) |
| OS patches | None | apt-get update && apt-get upgrade |
| User | root | appuser (UID 10001, non-root) |
| HEALTHCHECK | None | HTTP check on /docs every 30s |
| .dockerignore | None | Excludes .git, .terraform, tfstate |

### 5.5 Deliverables

- Fully automated CI/CD pipeline (green on every push).
- 10-tool security scanning integrated into the pipeline.
- Hardened Dockerfile with non-root user and HEALTHCHECK.
- Dependabot configuration for automated dependency updates.
- Least-privilege GitHub Actions token (contents: read).
- All credentials stored as encrypted GitHub Secrets.

---

## 6. Week 4: Kubernetes Orchestration and Deployment

### 6.1 What Was Done

- Created 7 Kubernetes manifests: Namespace, Deployment, Service, ConfigMap, HPA, PDB, NetworkPolicy.
- Hardened the Deployment with full security context (non-root, read-only filesystem, dropped capabilities, seccomp profile, no privilege escalation, no service account token).
- Stored the PostgreSQL connection string in Azure Key Vault via Terraform.
- Injected the database password into the AKS cluster as a Kubernetes Secret.
- Deployed the application to AKS with a public LoadBalancer IP.
- Added an automated deploy job to the GitHub Actions pipeline using an Azure Service Principal.
- Achieved zero Checkov errors through a combination of fixes and documented risk acceptance.

### 6.2 Kubernetes Architecture

The deployment uses a dedicated learningsteps namespace with the following resources:

- **Deployment:** 1 replica (auto-scales to 5 via HPA), rolling update strategy (maxSurge: 1, maxUnavailable: 0), three health probes (startup, readiness, liveness).
- **Service:** LoadBalancer type, maps port 80 (public) to port 8000 (container).
- **ConfigMap:** Non-secret configuration (APP_NAME, LOG_LEVEL, ENVIRONMENT).
- **HPA:** Scales from 1 to 5 pods when CPU exceeds 70%.
- **PDB:** Ensures at least 1 pod remains available during maintenance.
- **NetworkPolicy:** Ingress allows port 8000 from anywhere. Egress allows port 5432 to the DB subnet (10.0.2.0/24) and port 53 (DNS) only. All other traffic is blocked.

### 6.3 Challenges and Solutions

**Challenge 1: AKS auto-stopped by subscription policy**
The AKS cluster was stopped by the midnight auto-stop policy, causing kubectl commands to fail.
*Solution:* Ran az aks start before each session. This is a daily routine going forward.

**Challenge 2: Old resources in default namespace**
After creating the dedicated learningsteps namespace, old resources remained in the default namespace, causing duplicate LoadBalancers and unnecessary costs.
*Solution:* Manually deleted the old Deployment, Service, and Secret from the default namespace.

**Challenge 3: Checkov flagged 30+ security findings**
Checkov identified issues across AKS, PostgreSQL, Key Vault, K8s manifests, and the Dockerfile. Many were enterprise-grade requirements inappropriate for a dev environment.
*Solution:* Fixed what was practical (security context, AKS upgrade channel, Azure Policy, Key Vault secret expiration, HEALTHCHECK, read-only filesystem) and documented risk acceptance for the rest in .checkov.yml. Every skipped check includes a rationale explaining why it is acceptable for the dev environment and what would change for production.

**Challenge 4: Terraform fmt failure in CI**
Two new lines added to main.tf had incorrect indentation, causing the terraform fmt -check step to fail.
*Solution:* Ran terraform fmt locally to auto-fix formatting, then committed the corrected file. This reinforced the value of running terraform fmt before every commit.

**Challenge 5: Service Principal for automated deployment**
The GitHub Actions robot needed permission to deploy to AKS, requiring an Azure identity.
*Solution:* Created a Service Principal with az ad sp create-for-rbac scoped to the resource group with Contributor role. The credentials were stored as the AZURE_CREDENTIALS GitHub Secret.

### 6.4 The Full Automated Pipeline

The final pipeline executes on every git push:

git push
|
v
Job 1: build-and-scan (7-10 minutes)
|-- Checkout code
|-- Build Docker image
|-- Hadolint (Dockerfile)
|-- Trivy (image CVEs, HARD GATE)
|-- Bandit (Python code)
|-- pip-audit (Python deps)
|-- Semgrep (deep analysis)
|-- terraform fmt (HARD GATE)
|-- terraform validate (HARD GATE)
|-- tfsec (IaC)
|-- Checkov (IaC + K8s + Docker)
|-- Kube-score (K8s)
|-- Push to ACR (commit SHA tag)
|
v (only if all green)
Job 2: deploy (2-3 minutes)
|-- Azure Login (Service Principal)
|-- Connect to AKS
|-- Apply K8s manifests (rolling update)
|-- Replace image tag with commit SHA
|
v
Live at http://20.4.140.251/docs


### 6.5 Deliverables

- Live application accessible at http://20.4.140.251/docs.
- 7 Kubernetes manifests with full security hardening.
- Automated deploy job in the CI/CD pipeline.
- Zero Checkov errors (all findings resolved or documented).
- Database secrets stored in Key Vault with expiration dates.
- Complete end-to-end automation from git push to live deployment.

---

## 7. Results and Metrics

### 7.1 Final Infrastructure

| Category | Count |
|----------|-------|
| Azure resources (Terraform-managed) | 15+ |
| Kubernetes manifests | 7 |
| Security scanning tools | 10 |
| GitHub Secrets | 3 (ACR_USERNAME, ACR_PASSWORD, AZURE_CREDENTIALS) |
| Key Vault secrets | 2 (pg-admin-password, pg-connection-string) |
| CI/CD pipeline jobs | 2 (build-and-scan, deploy) |
| Pipeline steps | 16 |
| Checkov errors | 0 (from 30+ initial findings) |
| Trivy HIGH/CRITICAL CVEs | 0 fixable |
| Deployment downtime | 0 seconds (rolling updates) |

### 7.2 Reproducibility Test

The entire infrastructure can be destroyed and recreated with two commands:

    cd infra-terraform
    terraform destroy
    terraform apply

This recreates all 15+ Azure resources identically. The application is then deployed automatically by the CI/CD pipeline on the next git push.

### 7.3 Security Posture

| Layer | Before Project | After Project |
|-------|---------------|---------------|
| Container | Ran as root, Debian testing, no health check | Non-root (UID 10001), Debian stable, HEALTHCHECK, read-only FS, all capabilities dropped |
| Network | Public VM, all ports open | Private VNet, NSGs, K8s NetworkPolicy, private PostgreSQL |
| Secrets | Hardcoded or in .env files | Azure Key Vault with expiration, K8s Secrets, GitHub encrypted Secrets |
| Code | No scanning | Bandit + Semgrep on every push |
| Dependencies | No monitoring | Trivy + pip-audit + Dependabot |
| Infrastructure | Manual, no audit trail | Terraform (version-controlled), tfsec + Checkov scanning |
| Access Control | Admin everywhere | Least-privilege RBAC (AcrPull, KV Secrets User, contents:read) |
| Deployment | Manual SSH + docker run | Fully automated via GitHub Actions |

---

## 8. Cost Analysis

| Resource | Tier | Monthly Cost |
|----------|------|-------------|
| AKS (1x D2s_v6) | Standard | $60-75 |
| PostgreSQL Flexible Server | B1ms Burstable | $13-18 |
| Azure Container Registry | Basic | $5 |
| Key Vault | Standard | $1-3 |
| Load Balancer + Public IP | Basic | $3 |
| VNet, DNS, NSGs | - | Free |
| GitHub Actions | Free tier (2000 min/month) | $0 |
| **Total** | | **$82-104** |

**Cost optimization measures:**
- Auto-stop policy shuts down AKS at midnight UTC (saves ~50% on compute).
- Burstable B1ms tier for PostgreSQL (cheapest available).
- Basic ACR tier (sufficient for single-image projects).
- Single AKS node (HPA scales up only under load).
- terraform destroy available for complete cost elimination when not in use.

---

## 9. Key Lessons Learned

### Technical Lessons

1. **Infrastructure as Code is non-negotiable.** The pre-project manual deployment took days of debugging and was impossible to reproduce. Terraform reduced the entire infrastructure to a single terraform apply command.

2. **Security scanning must block the pipeline, not just warn.** A warning that nobody reads is useless. Trivy is configured as a hard gate: if fixable HIGH or CRITICAL vulnerabilities exist, the deployment stops.

3. **Private networking by default.** The PostgreSQL database has no public endpoint. It is accessible only from the AKS subnet via NSG rules and VNet delegation. This eliminates an entire attack surface.

4. **Least privilege everywhere.** AKS gets AcrPull (read-only image access), not Owner. The pipeline token gets contents: read, not write. The Service Principal is scoped to a single resource group. Every identity has the minimum permissions needed.

5. **Secrets belong in a vault with expiration dates.** Database credentials are generated by Terraform, stored in Azure Key Vault with a one-year expiration, and injected into Kubernetes as Secrets. They never appear in code, config files, or git history.

6. **Containers must be hardened.** Running as root, with full Linux capabilities, on a writable filesystem, without health checks is the default — and it is dangerous. The hardened Dockerfile and security context eliminate entire categories of container escape attacks.

7. **ignore-unfixed is a real-world necessity.** Blocking the pipeline on OS-level CVEs that the vendor has not patched means the pipeline is permanently broken. The professional approach is to ignore unfixable vulnerabilities while blocking on fixable ones.

8. **Rolling updates with maxUnavailable: 0 means zero-downtime deployments.** Kubernetes starts the new pod before killing the old one. Users never see an error during updates.

9. **Every skipped security check must be documented.** The .checkov.yml file contains 22 skipped checks, each with a rationale. Risk acceptance is not the same as ignorance. A reviewer can see that each finding was evaluated and a conscious decision was made.

10. **Defense in depth is essential.** No single security layer is sufficient. The project uses NSGs + NetworkPolicy + RBAC + private networking + secret management + container hardening + code scanning + image scanning + IaC scanning. An attacker would need to bypass all of these layers.

### Process Lessons

11. **Start with the simplest possible deployment, then harden.** Week 1 was just "make it run." Security hardening came in Weeks 3-4. Trying to do everything at once leads to paralysis.

12. **Read error messages carefully.** Every Azure error message contains the exact reason for failure and often a link to documentation. The MissingSubscriptionRegistration, K8sVersionNotSupported, and ServiceCidrOverlap errors were all solved by reading the error text.

13. **Automate the boring stuff.** The try-sizes.ps1 script that tested 8 VM sizes automatically saved hours of manual terraform apply cycles. The CI/CD pipeline saves hours of manual deployment on every push.

14. **Git history matters.** Accidentally pushing 238 MB of binaries to GitHub required a git reset to fix. Proper .gitignore files from the start would have prevented this.

15. **Document everything.** The README, the REPORT, the .checkov.yml rationales, the commit messages — documentation is what separates a project that works from a project that others can understand and maintain.

---

## 10. Future Improvements

| Priority | Improvement | Effort | Impact |
|----------|------------|--------|--------|
| High | Custom domain + HTTPS (TLS) | 1 week | Eliminates "Not Secure" browser warning |
| High | Prometheus + Grafana monitoring | 2 weeks | Real-time dashboards for CPU, memory, request latency |
| Medium | ArgoCD (GitOps) | 1 week | Pull-based deployments, audit trail |
| Medium | Multi-environment (dev/staging/prod) | 2-3 weeks | Separate environments with branch-based deploys |
| Medium | Image signing with Cosign | 1 week | Cryptographic verification of image provenance |
| Low | Microsoft Defender for Cloud | 30 min | Cloud-level threat detection |
| Low | Helm chart packaging | 1 week | Reusable, parameterized K8s deployments |

---

## 11. Conclusion

This project demonstrates that a production-grade DevSecOps pipeline is achievable in four weeks, even starting from zero cloud experience. The final system features:

- **Full automation:** From git push to live deployment in under 15 minutes, with zero manual steps.
- **Comprehensive security:** 10 scanning tools covering code, dependencies, containers, infrastructure, and orchestration.
- **Zero-downtime deployments:** Rolling updates ensure users never experience interruption.
- **Complete reproducibility:** terraform destroy + terraform apply recreates the entire environment identically.
- **Defense in depth:** Seven layers of security from network to application to secrets.
- **Cost awareness:** Under $100/month with auto-stop and budget-conscious resource selection.

The journey from a failed manual VM deployment to a hardened, automated Kubernetes pipeline reinforced the core DevOps principle: **automate everything, secure everything, document everything.**

---

*Report prepared by Moh (nrikmoh) as part of a hands-on DevSecOps learning project.*
*Repository: https://github.com/nrikmoh/learningsteps-devops*
*Live Application: http://20.4.140.251/docs*
