After Terraform has applied and GitHub Actions has pushed the three images, use this deployment order.
Terraform / ECR → connect kubectl → ALB controller → External Secrets →
Argo CD → create Argo Applications → sync Applications → verify pods/ingress
1. Connect your terminal to EKS. Run this manually (the phase6_05 script has an incorrect Terraform path):
aws eks update-kubeconfig --region us-east-1 --name pharma-dev-cluster
kubectl get nodes
2. Install the AWS Load Balancer Controller.
cd infra
python3 scripts/phase6_06_install_alb_controller.py
3. Install External Secrets Operator.
python3 scripts/phase6_07_install_external_secrets.py
4. Install Argo CD.
cd ../gitops
bash scripts/setup-argocd.sh
5. Create the Argo CD project and four Applications.
kubectl apply -f argocd/projects/pharma-project.yaml

kubectl apply \
  -f argocd/applications/pharma-shared-dev.yaml \
  -f argocd/applications/pharma-frontend-dev.yaml \
  -f argocd/applications/pharma-product-service-dev.yaml \
  -f argocd/applications/pharma-order-service-dev.yaml
6. Your Applications do not currently have automated sync enabled, so trigger a sync for each:
for app in pharma-shared-dev pharma-frontend-dev pharma-product-service-dev pharma-order-service-dev; do
  kubectl patch application "$app" -n argocd \
    --type merge -p '{"operation":{"sync":{}}}'
done
7. Verify:
kubectl get applications -n argocd
kubectl get pods,services,ingress -n pharma-app
kubectl get externalsecret,secret -n pharma-app
Important: before step 5 can fully work, the current GitOps configuration has three blockers:
- The shared chart claims to create an ExternalSecret, but it only contains a ClusterSecretStore; no ExternalSecret template exists. Therefore postgres-secret will not be created.
- Terraform creates the Secrets Manager secret but does not create a secret version because manage_secret_version defaults to false. It therefore has no DB credentials for External Secrets to copy.
- RDS hostnames are hard-coded in the three values-dev.yaml files. A newly created RDS instance will have a different endpoint.
So the controllers and Argo CD can be installed now, but the backend pods will not become ready until those three GitOps/secret items are fixed. Also, don’t use k8s/ for this AWS deployment—it deploys a local PostgreSQL setup, whereas the GitOps Helm charts are intended to use RDS.

____________________________________________________________________________________

Step 1 — Connect to the correct EKS cluster
Every time you start working, open your terminal and run:

aws eks update-kubeconfig --region us-east-1 --name pharma-dev-cluster


Verify the cluster and nodes:
kubectl get nodes


Expected: your EKS worker nodes show Ready.
Step 2 — Check whether Argo CD is already installed

kubectl get pods -n argocd


If the Argo CD pods are running, skip the installation step. If the namespace or installation is missing, install Argo CD only then:

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -


kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


Wait for Argo CD to become ready:

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s


Don't reinstall Argo CD when it is already healthy.
Step 3 — Go to the GitOps repository

cd ~/Pharma-app/pharma-devops-microservices/gitops


Update your local repository:

git pull --ff-only origin main


This ensures you use the latest committed manifests.
Step 4 — Apply the Argo CD project

kubectl apply -f argocd/projects/pharma-project.yaml


This creates or updates the Argo CD project that groups your Applications and defines their permitted sources and destinations.
Step 5 — Create or update the four Applications
Run this single command:

kubectl apply \
  -f argocd/applications/pharma-shared-dev.yaml \
  -f argocd/applications/pharma-frontend-dev.yaml \
  -f argocd/applications/pharma-product-service-dev.yaml \
  -f argocd/applications/pharma-order-service-dev.yaml


These apply commands are repeatable: they create missing Application objects or update existing ones. They do not require deleting Applications first.

Your Applications do not currently have automated sync enabled, so trigger a sync 


for each:
for app in pharma-shared-dev pharma-frontend-dev pharma-product-service-dev pharma-order-service-dev; do
  kubectl patch application "$app" -n argocd \
    --type merge -p '{"operation":{"sync":{}}}'
done


Step 6 — Check synchronization

kubectl get applications -n argocd


Your desired result is:
Application	Sync	Health

pharma-shared-dev	Synced	Healthy
pharma-frontend-dev	Synced	Healthy
pharma-order-service-dev	Synced	Healthy
pharma-product-service-dev	Synced	Healthy

If an Application shows OutOfSync, inspect it first:
kubectl describe application pharma-frontend-dev -n argocd


If the configuration is correct and there are no ownership conflicts, you can trigger a sync for that Application:

kubectl patch application pharma-frontend-dev -n argocd --type merge -p '{"operation":{"sync":{}}}'


Repeat for another Application only if it needs syncing. Wait and recheck status afterward.
Step 7 — Verify the workloads

kubectl get pods -n pharma-app


Then check the Ingress:

kubectl get ingress -n pharma-app


login to argo cd UI

kubectl port-forward svc/argocd-server -n argocd 8080:443

to get password:

kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode; echo