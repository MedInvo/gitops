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

kubectl apply -f argocd/applications/pharma-shared-dev.yaml -f argocd/applications/pharma-frontend-dev.yaml -f argocd/applications/pharma-order-service-dev.yaml -f argocd/applications/pharma-product-service-dev.yaml


These apply commands are repeatable: they create missing Application objects or update existing ones. They do not require deleting Applications first.
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