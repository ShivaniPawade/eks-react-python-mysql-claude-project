# 3-Tier EKS App — Complete Deploy Guide
## React → Python/Flask → MySQL RDS

---

## Prerequisites
```bash
# Tools you need installed
aws --version          # AWS CLI v2
terraform --version    # >= 1.5
kubectl version        # any recent
docker --version       # for building images
```

---

## Step 1 — Terraform: Provision Infrastructure

```bash
cd terraform/

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set db_password to something real

# Initialise — downloads providers, sets up S3 backend
terraform init

# Review what will be created
terraform plan -var-file=terraform.tfvars

# Apply — takes ~15 min (EKS cluster creation)
terraform apply -var-file=terraform.tfvars

# Save outputs — you'll need these
terraform output rds_endpoint      # RDS host for the K8s secret
terraform output ecr_backend_url   # ECR URL for docker push
terraform output ecr_frontend_url
```

---

## Step 2 — Connect kubectl to EKS

```bash
# Update your kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name myapp-eks

# Verify nodes are Ready
kubectl get nodes

# Expected output:
# NAME                         STATUS   ROLES    AGE
# ip-10-0-1-xxx.ec2.internal   Ready    <none>   5m
# ip-10-0-2-xxx.ec2.internal   Ready    <none>   5m
```

---

## Step 3 — Build & Push Docker Images to ECR

```bash
# Get your AWS account ID
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)   # 439475769439
REGION=us-east-1

# Login to ECR (token expires in 12h)
aws ecr get-login-password --region $REGION \
  | docker login --username AWS \
    --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# Build & push BACKEND
cd backend/
docker build -t backend .
docker tag backend:latest $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/backend:latest
docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/backend:latest

# Build & push FRONTEND
cd ../frontend/
docker build -t frontend .
docker tag frontend:latest $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/frontend:latest
docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/frontend:latest
```

---

## Step 4 — Update K8s Manifests with Your ECR URLs

```bash
# In k8s/02-backend.yaml, replace:
#   <YOUR_ECR_ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/backend:latest
# with your actual ECR URL from terraform output

# In k8s/03-frontend.yaml, same for frontend image

# Quick sed replace:
sed -i "s|<YOUR_ECR_ACCOUNT>|$ACCOUNT|g" k8s/02-backend.yaml k8s/03-frontend.yaml
sed -i "s|<REGION>|$REGION|g" k8s/02-backend.yaml k8s/03-frontend.yaml
```

---

## Step 5 — Create K8s Secret with RDS Credentials

```bash
# Get your RDS endpoint from terraform
RDS_HOST=$(cd terraform && terraform output -raw rds_endpoint)

# Create the secret directly (safer than editing YAML with real passwords)
kubectl create namespace app

kubectl create secret generic db-secret \
  --namespace app \
  --from-literal=DB_HOST=myapp-mysql.c4tqwcuewjko.us-east-1.rds.amazonaws.com \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASSWORD="shortbust123#" \
  --from-literal=DB_NAME=appdb

# Verify secret exists (values will be masked)
kubectl get secret db-secret -n app
```

---

## Step 6 — Deploy to EKS

```bash
cd k8s/

# Apply all manifests in order
kubectl apply -f 00-namespace.yaml
kubectl apply -f 02-backend.yaml
kubectl apply -f 03-frontend.yaml

# Watch pods come up
kubectl get pods -n app -w

# Expected after ~60s:
# NAME                       READY   STATUS    RESTARTS
# backend-xxx                1/1     Running   0
# backend-yyy                1/1     Running   0
# frontend-xxx               1/1     Running   0
# frontend-yyy               1/1     Running   0
```

---

## Step 7 — Get the App URL

```bash
# Wait for LoadBalancer to get an external IP (~2 min)
kubectl get svc frontend-svc -n app -w

# Once EXTERNAL-IP shows an AWS hostname:
# NAME           TYPE           EXTERNAL-IP
# frontend-svc   LoadBalancer   xxx.us-east-1.elb.amazonaws.com

# Open in browser:
echo "http://$(kubectl get svc frontend-svc -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

---

## Verify Everything Works

```bash
# 1. Check all pods are Running
kubectl get pods -n app

# 2. Check backend can reach RDS (look for no DB errors in logs)
kubectl logs -l app=backend -n app

# 3. Check frontend logs
kubectl logs -l app=frontend -n app

# 4. Hit backend health directly from inside cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n app \
  -- curl http://backend-svc.app.svc.cluster.local/health
# Expected: {"status": "ok"}

# 5. Hit the API
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n app \
  -- curl http://backend-svc.app.svc.cluster.local/api/users
# Expected: []  (empty array, no users yet)
```

---

## Common Errors & Fixes

### Pods in ImagePullBackOff
```bash
kubectl describe pod <pod-name> -n app
# Look at Events — usually ECR auth or wrong image URL
# Fix: re-run docker push, check image URL in manifest
```

### Backend CrashLoopBackOff
```bash
kubectl logs <pod-name> -n app --previous
# Usually DB connection error — check secret values
kubectl get secret db-secret -n app -o jsonpath='{.data.DB_HOST}' | base64 -d
```

### Frontend can't reach backend
```bash
# REACT_APP_API_URL is baked at build time
# If you changed it after build, you must rebuild the Docker image
# In K8s: env vars in pod spec are for server-side only
# React env vars must be set BEFORE npm run build
```

### RDS connection refused
```bash
# Check security group — EKS node SG must be allowed on port 3306 in RDS SG
# Terraform handles this automatically if you used the provided main.tf
```

---

## Teardown (avoid AWS charges)
```bash
# Delete K8s resources first (removes LoadBalancer from AWS)
kubectl delete -f k8s/

# Then destroy infrastructure
cd terraform/
terraform destroy -var-file=terraform.tfvars
```

---

## What's Running After Deploy

```
Internet
    │
    ▼
[ALB / LoadBalancer]        ← AWS creates this from frontend-svc
    │
    ▼
[frontend pods x2]          ← React app served by nginx
    │  (ClusterIP DNS)
    ▼
[backend pods x2]           ← Flask API, ClusterIP only
    │  (private subnet)
    ▼
[RDS MySQL]                 ← Not in K8s, managed AWS service
```

---

## Next Practice Add-ons (Phase 2)
Once the app is running, practice these EKS objects on it:

1. **HPA** — `kubectl autoscale deployment backend --cpu-percent=50 --min=2 --max=5`
2. **Ingress** — replace LoadBalancer Service with ALB Ingress Controller
3. **ConfigMap** — move non-secret env vars out of deployment spec
4. **Resource Quotas** — add namespace-level limits
5. **NetworkPolicy** — restrict frontend → backend → RDS traffic only
6. **PodDisruptionBudget** — ensure rolling updates don't kill all pods
7. **Liveness/Readiness tuning** — adjust thresholds, test failure scenarios
