# Argo CD Setup for Pharma Dev Environment

This guide shows the correct order to install and validate the Kubernetes platform pieces after Terraform has applied and the GitHub Actions pipeline has pushed the Docker images.

## Deployment order

Terraform / ECR -> connect kubectl -> ALB controller -> External Secrets -> Argo CD -> create Argo Applications -> sync Applications -> verify pods / ingress

## Prerequisites

Make sure the following are already complete before starting:

- Terraform has created the AWS infrastructure
- ECR repositories exist
- GitHub Actions has pushed the three application images
- You have AWS CLI access and kubectl configured

## Step 1: Connect to the correct EKS cluster

Every time you start working, run:

```bash
aws eks update-kubeconfig --region us-east-1 --name pharma-dev-cluster
kubectl get nodes
```

Expected result: EKS worker nodes show `Ready`.

## Step 2: Install the AWS Load Balancer Controller

```bash
cd infra
python3 scripts/02_install_alb_controller.py
```

This installs the AWS Load Balancer Controller required for Ingress resources.

## Step 3: Install the External Secrets Operator

```bash
python3 scripts/03_install_external_secrets.py
```

This installs the controller needed to read secrets from AWS Secrets Manager into Kubernetes.

## Step 4: Install Argo CD

First, go to the GitOps repo:

```bash
cd ../gitops
```

Then install Argo CD if it is not already present:

```bash
kubectl get pods -n argocd
```

If Argo CD is not running, install it:

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

Do not reinstall Argo CD if it is already healthy.

## Step 5: Pull the latest GitOps manifests

```bash
git pull --ff-only origin main
```

This ensures you apply the latest committed manifests.

## Step 6: Create the Argo CD project

```bash
kubectl apply -f argocd/projects/pharma-project.yaml
```

This creates or updates the project that groups the Applications and defines their allowed sources and destinations.

## Step 7: Create or update the four Applications

Run the following command:

```bash
kubectl apply \
  -f argocd/applications/pharma-shared-dev.yaml \
  -f argocd/applications/pharma-frontend-dev.yaml \
  -f argocd/applications/pharma-product-service-dev.yaml \
  -f argocd/applications/pharma-order-service-dev.yaml
```

These apply commands are idempotent: they create missing Application objects or update existing ones without requiring deletion first.

## Step 8: Trigger sync for each Application

Applications do not currently have automated sync enabled, so trigger a sync manually:

```bash
for app in pharma-shared-dev pharma-frontend-dev pharma-product-service-dev pharma-order-service-dev; do
  kubectl patch application "$app" -n argocd \
    --type merge -p '{"operation":{"sync":{}}}'
done
```

## Step 9: Check synchronization status

```bash
kubectl get applications -n argocd
```

Expected output:

```text
Application                   Sync    Health
pharma-shared-dev            Synced  Healthy
pharma-frontend-dev          Synced  Healthy
pharma-order-service-dev     Synced  Healthy
pharma-product-service-dev   Synced  Healthy
```

If an Application is `OutOfSync`, inspect it first:

```bash
kubectl describe application pharma-frontend-dev -n argocd
```

If the configuration is correct and there are no ownership conflicts, trigger sync for just that Application:

```bash
kubectl patch application pharma-frontend-dev -n argocd --type merge -p '{"operation":{"sync":{}}}'
```

Repeat only for the Applications that need syncing, then recheck status.

## Step 10: Verify workloads and ingress

```bash
kubectl get pods -n pharma-app
kubectl get ingress -n pharma-app
kubectl get pods,services,ingress -n pharma-app
kubectl get externalsecret,secret -n pharma-app
```

Check that workloads are running and ingress is created successfully.

## Step 11: Access the Argo CD UI

Port-forward the Argo CD server:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Get the admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode; echo
```

Then open the UI in a browser at:

```text
https://localhost:8080
```

Login with username `admin` and the password shown above.

---

## Important blockers before the app can become fully ready

Before step 7 can fully work, the current GitOps configuration has three blockers:

- The shared chart claims to create an `ExternalSecret`, but it only contains a `ClusterSecretStore`; no `ExternalSecret` template exists. Therefore `postgres-secret` will not be created.
- Terraform creates the Secrets Manager secret but does not create a secret version because `manage_secret_version` defaults to `false`. It therefore has no DB credentials for External Secrets to copy.
- RDS hostnames are hard-coded in the three `values-dev.yaml` files. A newly created RDS instance will have a different endpoint.

Because of these issues, the controllers and Argo CD can be installed now, but the backend pods will not become ready until these GitOps and secret issues are fixed.

Also, do not use `k8s/` for this AWS deployment. Use the correct repo and paths for the AWS/EKS environment.

---

## Quick summary

If you want the shortest working flow, use this sequence:

```bash
aws eks update-kubeconfig --region us-east-1 --name pharma-dev-cluster
cd infra
python3 scripts/phase6_06_install_alb_controller.py
python3 scripts/phase6_07_install_external_secrets.py
cd ../gitops
bash scripts/setup-argocd.sh
kubectl apply -f argocd/projects/pharma-project.yaml
kubectl apply \
  -f argocd/applications/pharma-shared-dev.yaml \
  -f argocd/applications/pharma-frontend-dev.yaml \
  -f argocd/applications/pharma-product-service-dev.yaml \
  -f argocd/applications/pharma-order-service-dev.yaml
for app in pharma-shared-dev pharma-frontend-dev pharma-product-service-dev pharma-order-service-dev; do
  kubectl patch application "$app" -n argocd --type merge -p '{"operation":{"sync":{}}}'
done
kubectl get applications -n argocd
kubectl get pods,services,ingress -n pharma-app
kubectl get externalsecret,secret -n pharma-app
```

This order keeps the deployment consistent and makes troubleshooting easier.
