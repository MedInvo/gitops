# Argo CD Bootstrap Script

This script automates the Argo CD setup used for the Pharma DevOps EKS project.

## What it does

1. Verifies `kubectl` and checks that the current context appears to target `pharma-dev-cluster`.
2. Creates the `argocd` namespace if missing.
3. Installs or updates Argo CD from the official manifest.
4. Waits for Argo CD deployments and Application/AppProject CRDs.
5. Applies the existing `argocd/projects/pharma-project.yaml` and `argocd/applications/pharma-dev.yaml` when run from the GitOps repo. Otherwise, it applies equivalent bootstrap manifests.
6. Prints the application status and Argo CD pods.

The script is safe to rerun for ordinary setup/update operations. It does not uninstall resources.

## Requirements

- `kubectl`
- Kubernetes access to the intended EKS cluster
- GitOps repository files if you want the script to apply the committed manifests
- Network access to GitHub from the machine running the script

## Run it

From the local GitOps repository:

```bash
cd ~/Pharma-app/pharma-devops-microservices/gitops
chmod +x scripts/setup-argocd.sh
./scripts/setup-argocd.sh
```

If the script is saved in a different location, run it by its actual path. The default context check expects a context containing `pharma-dev-cluster`.

## Pin an Argo CD version (recommended for repeatable setups)

The default uses the official `stable` manifest, which can change over time. To pin a release, set `ARGOCD_VERSION` to a valid Argo CD release tag:

```bash
ARGOCD_VERSION=vX.Y.Z ./scripts/setup-argocd.sh
```

Replace `vX.Y.Z` with a real release tag you have chosen and verified before running.

## Optional configuration

```bash
EXPECTED_CLUSTER=pharma-dev-cluster \
ARGOCD_NAMESPACE=argocd \
APP_NAMESPACE=pharma-app \
GITOPS_REPO_URL=https://github.com/MedInvo/gitops.git \
GITOPS_BRANCH=main \
GITOPS_PATH=charts/pharma-app \
./scripts/setup-argocd.sh
```

For a private GitOps repository, configure repository credentials in Argo CD separately. Do not put tokens or passwords in this script or commit them to Git.

## Verify the setup

```bash
kubectl get pods -n argocd
kubectl get appprojects -n argocd
kubectl get applications -n argocd
kubectl get application pharma-dev -n argocd \
  -o jsonpath='{.status.sync.status}{" | "}{.status.health.status}{"\\n"}'
```

Watch reconciliation:

```bash
kubectl get application pharma-dev -n argocd -w
```

## Access the UI locally

Terminal 1:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080`.

Terminal 2 — initial admin password (keep it private):

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 --decode
echo
```

## Troubleshooting

```bash
kubectl describe application pharma-dev -n argocd
kubectl get events -n argocd --sort-by=.lastTimestamp
kubectl get pods -n argocd
kubectl get pods -n pharma-app
kubectl describe clustersecretstore pharma-aws-secrets
kubectl describe externalsecret pharma-db-secret -n pharma-app
```

If sync fails with `ClusterSecretStore is not permitted`, confirm the AppProject includes:

```yaml
clusterResourceWhitelist:
  - group: ""
    kind: Namespace
  - group: external-secrets.io
    kind: ClusterSecretStore
```

Keep this permission limited to the specific cluster-scoped resource needed by the chart.

## Important notes

- Argo CD installs into EKS; it is not installed by the GitOps chart itself.
- The GitOps Application watches the `main` branch and `charts/pharma-app`, using `values.yaml` and `values-dev.yaml`.
- The Application has automated sync, prune, and self-heal enabled.
- The script does not install Terraform, EKS, External Secrets Operator, or provision AWS infrastructure.
- The script does not expose the Argo CD UI publicly. Port-forwarding is intended for local access.
- Review the official Argo CD release/version and installation guidance before production use.
