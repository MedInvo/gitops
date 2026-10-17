# MedInvo GitOps

This repository contains the GitOps manifests, Helm charts and helper scripts used to deploy the Pharma microservices platform to an EKS cluster via Argo CD.

### Stack
- Language(s): Go Template (Helm chart templates), Shell (helper scripts)
- Tools: Kubernetes, Helm, Argo CD, AWS EKS

## Top-level repository structure
```
README.md
README-ArgoCD-Setup.md    # Operational runbook for installing Argo CD and syncing apps
.argocd/ or argocd/       # Argo CD manifests: Applications and Projects
backups/                  # Backup/restore manifests and notes (Velero, etc.)
charts/                   # Helm charts for services (charts/pharma-*)
environments/             # Environment-specific values/overlays (dev/staging/prod)
scripts/                  # Utility scripts for bootstrap, CI helpers, or convenience
.gitignore
```

## Directory explanations
- argocd/ (or .argocd/):
  - Contains Argo CD Application YAMLs (argocd/applications/) and Project YAMLs (argocd/projects/).
  - Each Application points at a chart path under charts/ and to the `main` branch; Argo CD uses these to create and reconcile Helm releases in the cluster.

- charts/:
  - Helm charts for each microservice and shared components (e.g. pharma-frontend, pharma-order-service, pharma-product-service, pharma-shared).
  - Each chart includes templates/, Chart.yaml, and values files (values.yaml, values-dev.yaml). Edit values files for environment-specific configuration.

- environments/:
  - Holds environment-specific overlays or values files which are referenced by Argo CD or CI/CD pipelines to produce the correct helm values per environment (dev, staging, prod).

- backups/:
  - Backup manifests, configuration, or runbooks (Velero, snapshots, or custom backup procedures) used to protect cluster state and persistent data.

- scripts/:
  - Helper scripts for bootstrapping the cluster, automating repetitive tasks, or CI helper scripts. Examples include scripts to generate secrets, run local validations, or perform bulk kubectl/helm operations.

## How it fits together (brief)
1. Developers update Helm chart values or chart templates under charts/ and push changes to this repo.
2. Argo CD monitors this repository; Application manifests in argocd/applications/ tell Argo CD which chart path and values to deploy to which namespace (e.g. `pharma-app`).
3. Argo CD reconciles the desired state by installing/upgrading Helm releases on the target EKS cluster.
4. environments/ and values-*.yaml files provide the environment-specific configuration used by those Helm releases.

## Quick operational notes
- The included README-ArgoCD-Setup.md is an operational runbook: follow it to connect to the EKS cluster, install Argo CD, apply projects and applications, and verify sync/health.
- Application manifests reference value files such as values.yaml and values-dev.yaml — check charts/* for the concrete values to change per environment.

---

If you'd like, I can also:
- Add a short CONTRIBUTING.md with PR and branching guidance for GitOps changes.
- Add a top-level CHARTS.md that documents each chart's configurable values and expected secrets.
