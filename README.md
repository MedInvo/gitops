# MedInvo GitOps

This directory is the **desired-state repository** for deploying the Pharma
frontend and backend services to Kubernetes. It contains Argo CD configuration
and Helm charts; it does not contain application source code or build container
images.

## How the pieces fit together

```text
Frontend/backend source change
             |
             v
  GitHub Actions tests and scans
             |
             v
       Build image -> ECR
             |
             v
 Update the image tag in this repo
             |
             v
 Argo CD reads the chart and values
             |
             v
      EKS namespace: pharma-app
```

The CI workflows build and publish images, then commit their tags to the
development values files here. Argo CD reads this repository and compares the
declared chart configuration with the resources in the cluster. An Argo CD
Application in this repo is a Kubernetes custom resource: it tells Argo CD
which chart and values to use, which Git revision to read, and where to deploy.

The development Applications point at the `main` branch of
[`MedInvo/gitops`](https://github.com/MedInvo/gitops), with the chart as their
source path. The image tag is therefore changed in Git first; Argo CD then
observes the changed desired state.

## Repository map

```text
gitops/
├── argocd/
│   ├── applications/
│   │   ├── pharma-shared-dev.yaml
│   │   ├── pharma-frontend-dev.yaml
│   │   ├── pharma-order-service-dev.yaml
│   │   ├── pharma-product-service-dev.yaml
│   │   ├── pharma-staging.yaml             # placeholder; currently empty
│   │   └── pharma-prod.yaml                # placeholder; currently empty
│   └── projects/
│       └── pharma-project.yaml
├── charts/
│   ├── pharma-shared/                      # shared config and secrets wiring
│   ├── pharma-frontend/                    # frontend Deployment, Service, Ingress
│   ├── pharma-order-service/               # order Deployment and Service
│   └── pharma-product-service/             # product Deployment and Service
├── scripts/
│   └── setup-argocd.sh                     # version-pinned Argo CD installation
├── README.md
└── README-ArgoCD-Setup.md                  # cluster setup and operating steps
```

### Argo CD project and Applications

- `argocd/projects/pharma-project.yaml` defines the `pharma-project` AppProject.
  It restricts sources to the GitOps repository and destinations to the
  in-cluster API server and the `pharma-app` namespace. It also declares the
  cluster-scoped resources the charts need.
- The four `*-dev.yaml` Application manifests each select one chart under
  `charts/`, use the `main` Git revision, and layer `values.yaml` with
  `values-dev.yaml`. They deploy to `pharma-app`.
- `CreateNamespace=true` allows Argo CD to create that destination namespace.
- The Applications currently configure namespace creation, but do **not**
  enable Argo CD automated sync. Argo CD can report a Git change as
  `OutOfSync`; an operator must sync it from the UI or CLI unless automated
  sync is deliberately configured.
- The staging and production Application files are empty today. They are
  placeholders, not usable environment deployments.

### Helm charts and values

Each service chart keeps reusable defaults in `values.yaml` and the current
development-specific settings in `values-dev.yaml`. The Application manifests
load the defaults first and then the development overrides. Common values
include the namespace; the development files set image repositories/tags and
replica counts, plus service and database connection settings where applicable.

| Chart | Resources and purpose |
|---|---|
| `pharma-shared` | Creates `app-config`, a `ClusterSecretStore`, and an `ExternalSecret`. |
| `pharma-frontend` | Runs the frontend Deployment and ClusterIP Service; creates an ALB Ingress. |
| `pharma-order-service` | Runs the order-service Deployment and ClusterIP Service; configures its product-service URL and database settings. |
| `pharma-product-service` | Runs the product-service Deployment and ClusterIP Service, with readiness/liveness TCP probes and database settings. |

The frontend Ingress is configured for the AWS Load Balancer Controller and
references an ACM certificate. Ensure that certificate and its region are
appropriate for the target cluster before deploying to another environment.

### Shared configuration and secrets

The shared chart publishes non-secret connection settings in the `app-config`
ConfigMap. Its `ExternalSecret` asks External Secrets Operator to create the
Kubernetes Secret `postgres-secret` from the AWS Secrets Manager entry
`pharma-medinvo/dev/app-db`. The associated `ClusterSecretStore` uses AWS
Secrets Manager in `us-east-1` and a Kubernetes service account for AWS
identity.

This setup depends on External Secrets Operator and its CRDs being installed,
and on the referenced service account/IAM permissions and Secrets Manager
entry existing. The chart defines the integration; it does not install or
provision those prerequisites. Do not put database credentials in Helm values
or commit secret values to Git.

## Image update and deployment flow

1. A source repository's GitHub Actions workflow runs tests and quality/security
   checks, builds the service image, scans it, and publishes it to Amazon ECR.
2. On the configured deployment branch, the workflow checks out this repository
   and updates the relevant `image.tag` in a `values-dev.yaml` file.
3. The workflow commits and pushes that change to the GitOps repository.
4. Argo CD reads the changed chart values and reports whether the cluster is
   `OutOfSync`. Since automated sync is not currently enabled, sync the
   Application after reviewing the diff.
5. Kubernetes pulls the selected image and rolls out the Deployment. Confirm
   pod and ingress health in the cluster.

The current workflows use the frontend development values file for frontend
image tags and the order/product development files for backend image tags.
Review the workflows in the frontend and backend source repositories if
branch rules or image publication behavior change.

## Deploy or refresh the development Applications

Prerequisites: `kubectl` is installed and authenticated to the intended EKS
cluster; Argo CD is healthy; and any chart dependencies (including External
Secrets Operator and AWS Load Balancer Controller) are installed and configured.

From this directory, apply the project and the four development Applications:

```bash
kubectl apply -f argocd/projects/pharma-project.yaml

kubectl apply \
  -f argocd/applications/pharma-shared-dev.yaml \
  -f argocd/applications/pharma-frontend-dev.yaml \
  -f argocd/applications/pharma-order-service-dev.yaml \
  -f argocd/applications/pharma-product-service-dev.yaml
```

These commands are repeatable: they create missing Argo CD objects or update
their definitions. They do not themselves force a sync of every Application.

Check Application state and workloads:

```bash
kubectl get applications -n argocd
kubectl get pods,services,ingress -n pharma-app
```

If an Application is `OutOfSync`, inspect it before syncing:

```bash
kubectl describe application pharma-frontend-dev -n argocd
```

After confirming the desired change and resolving any configuration or
ownership issue, request a sync:

```bash
kubectl patch application pharma-frontend-dev -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

Replace the Application name as needed, then check its sync and health status
again. For cluster connection, Argo CD installation, and UI access instructions,
see [`README-ArgoCD-Setup.md`](./README-ArgoCD-Setup.md). The installation
script [`scripts/setup-argocd.sh`](./scripts/setup-argocd.sh) installs the
version pinned in that script.

## Making changes safely

- Change image tags in the appropriate development values file (normally the
  CI workflow does this); use immutable tags such as commit-SHA tags.
- Keep shared settings in the chart's defaults only when they genuinely apply
  to every environment. Put environment-specific values in environment
  overrides.
- Before adding staging or production, fill in and validate their Application
  manifests, values, repository/branch strategy, secrets, and AWS-specific
  settings. Do not assume the empty manifests are deployable.
- Render or lint a chart locally before applying changes, for example:

  ```bash
  helm lint charts/pharma-frontend \
    -f charts/pharma-frontend/values-dev.yaml
  helm template pharma-frontend charts/pharma-frontend \
    -f charts/pharma-frontend/values-dev.yaml
  ```

  Pass the corresponding environment values file when linting or rendering
  other charts as well; some templates require values supplied by that file.

- Review the rendered resources and the Argo CD diff before syncing changes to
  a live cluster.