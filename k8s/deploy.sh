#!/bin/bash
# =============================================================================
# Soirée — EKS + Istio Deployment Script
# Run from the project root after `terraform apply` has completed
# Usage: bash k8s/deploy.sh
# =============================================================================
set -e

CLUSTER_NAME="soiree-eks-cluster"
AWS_REGION="ap-southeast-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISTIO_VERSION="1.21.0"

echo "=== [1/6] Fetching Terraform outputs ==="
cd "$(dirname "$SCRIPT_DIR")/backend"

RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null | cut -d: -f1)
NOTIFY_API_URL=$(terraform output -raw notify_api_url 2>/dev/null)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "  RDS endpoint : $RDS_ENDPOINT"
echo "  Notify API   : $NOTIFY_API_URL"
echo "  Account ID   : $AWS_ACCOUNT_ID"

# =============================================================================
echo "=== [2/6] Updating kubeconfig for EKS ==="
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION"

kubectl cluster-info

# =============================================================================
echo "=== [3/6] Installing Istio ${ISTIO_VERSION} ==="

# Download istioctl if not present
if ! command -v istioctl &>/dev/null; then
  echo "  Downloading istioctl..."
  curl -sSL "https://istio.io/downloadIstio" | ISTIO_VERSION="$ISTIO_VERSION" sh -
  export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"
fi

# Install Istio with default profile
istioctl install --set profile=default -y

# Wait for Istio control plane to be ready
echo "  Waiting for Istio control plane..."
kubectl rollout status deployment/istiod -n istio-system --timeout=180s

# Apply custom Istio ingress gateway service (NLB)
kubectl apply -f "$SCRIPT_DIR/istio-ingress-service.yaml"

echo "  Waiting for Istio ingress gateway..."
kubectl rollout status deployment/istio-ingressgateway -n istio-system --timeout=120s

# =============================================================================
echo "=== [4/6] Applying base Kubernetes resources ==="

# Namespace with istio-injection enabled
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"

# ConfigMap — inject actual RDS endpoint from Terraform output
sed "s|DB_HOST: .*|DB_HOST: \"$RDS_ENDPOINT\"|" "$SCRIPT_DIR/configmap.yaml" | \
  kubectl apply -f -

# Kafka and Redis (supporting services)
kubectl apply -f "$SCRIPT_DIR/kafka.yaml"
kubectl apply -f "$SCRIPT_DIR/redis.yaml"

# Wait for supporting services
echo "  Waiting for Redis..."
kubectl rollout status deployment/redis -n soiree --timeout=120s || true

# =============================================================================
echo "=== [5/6] Building and pushing Docker images to ECR ==="

ECR_AUTH_URL="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Authenticate Docker to ECR
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_AUTH_URL"

PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

build_and_push() {
  local SERVICE="$1"
  local CONTEXT="$2"
  local ECR_REPO="$3"
  echo "  Building $SERVICE..."
  docker build -t "$SERVICE:latest" "$CONTEXT"
  docker tag "$SERVICE:latest" "$ECR_REPO:latest"
  docker push "$ECR_REPO:latest"
}

build_and_push "auth-service"   "$PROJECT_ROOT/services/auth-service"   "$ECR_AUTH_URL/soiree/auth-service"
build_and_push "event-service"  "$PROJECT_ROOT/services/event-service"  "$ECR_AUTH_URL/soiree/event-service"
build_and_push "rsvp-service"   "$PROJECT_ROOT/services/rsvp-service"   "$ECR_AUTH_URL/soiree/rsvp-service"
build_and_push "frontend"       "$PROJECT_ROOT/frontend"                "$ECR_AUTH_URL/soiree/frontend"

# Replace placeholder account ID in manifests and deploy
for MANIFEST in auth-service.yaml event-service.yaml rsvp-service.yaml frontend.yaml; do
  sed "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" "$SCRIPT_DIR/$MANIFEST" | \
    kubectl apply -f -
done

# Wait for all deployments to roll out
for DEP in auth-service event-service rsvp-service frontend; do
  echo "  Waiting for $DEP..."
  kubectl rollout status deployment/$DEP -n soiree --timeout=180s
done

# =============================================================================
echo "=== [6/6] Applying Istio traffic management ==="

kubectl apply -f "$SCRIPT_DIR/istio-peerauthentication.yaml"
kubectl apply -f "$SCRIPT_DIR/istio-gateway.yaml"
kubectl apply -f "$SCRIPT_DIR/istio-virtualservice.yaml"
kubectl apply -f "$SCRIPT_DIR/istio-destinationrules.yaml"

# =============================================================================
echo ""
echo "=== Deployment complete! ==="
echo ""

NLB_HOST=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo "  Istio NLB hostname : $NLB_HOST"
echo "  Namespace          : soiree"
echo ""
echo "  Next steps:"
echo "  1. Point dieunga.io.vn → $NLB_HOST in Route53 (or run: bash k8s/update-route53.sh)"
echo "  2. Verify services:  kubectl get pods -n soiree"
echo "  3. Verify Istio:     kubectl get pods -n istio-system"
echo "  4. Check mTLS:       istioctl authn tls-check -n soiree"
