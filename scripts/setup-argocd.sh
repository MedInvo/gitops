
#!/usr/bin/env bash
set -Eeuo pipefail

ARGOCD_VERSION="v3.5.5"
ARGOCD_NAMESPACE="argocd"
ARGOCD_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

command -v kubectl >/dev/null 2>&1 || {
  echo "ERROR: kubectl is not installed."
  exit 1
}

kubectl cluster-info >/dev/null

if ! kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  kubectl create namespace "$ARGOCD_NAMESPACE"
fi

echo "Installing Argo CD ${ARGOCD_VERSION} with server-side apply..."

kubectl apply --server-side -f "$ARGOCD_MANIFEST"

echo "Waiting for Argo CD deployments..."

kubectl rollout status deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" --timeout=300s

kubectl rollout status deployment/argocd-repo-server \
  -n "$ARGOCD_NAMESPACE" --timeout=300s

kubectl rollout status deployment/argocd-application-controller \
  -n "$ARGOCD_NAMESPACE" --timeout=300s

kubectl rollout status deployment/argocd-applicationset-controller \
  -n "$ARGOCD_NAMESPACE" --timeout=300s

echo "Checking required CRDs..."

kubectl get crd applications.argoproj.io
kubectl get crd appprojects.argoproj.io
kubectl get crd applicationsets.argoproj.io

echo "Argo CD installation checks completed."
