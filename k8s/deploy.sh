#!/bin/bash
# =============================================================================
# Soirée — EKS + Istio Deployment Script
# Run from the project root after `terraform apply` has completed
# Usage: bash k8s/deploy.sh
# =============================================================================
set -e

CLUSTER_NAME="soiree-eks-cluster"
AWS_REGION="ap-southeast-1"
ISTIO_VERSION="1.21.0"

BACKEND_DIR="backend"
K8S_DIR="k8s"

# Locate binaries — prefer .exe (Windows native) so kubeconfig paths match
find_bin() {
  command -v "$1.exe" 2>/dev/null || command -v "$1" 2>/dev/null || { echo "ERROR: '$1' not found in PATH."; exit 1; }
}

TERRAFORM=$(find_bin terraform)
AWS=$(find_bin aws)
KUBECTL=$(find_bin kubectl)
DOCKER=$(find_bin docker)

echo "  terraform : $TERRAFORM"
echo "  aws       : $AWS"
echo "  kubectl   : $KUBECTL"
echo "  docker    : $DOCKER"

echo "=== [1/6] Fetching Terraform outputs ==="

if [ ! -f "$BACKEND_DIR/terraform.tfstate" ]; then
  echo "ERROR: Cannot find terraform.tfstate in $BACKEND_DIR"
  echo "Make sure you run this script from the project root directory."
  exit 1
fi

RDS_ENDPOINT=$("$TERRAFORM" -chdir="$BACKEND_DIR" output -raw rds_endpoint | cut -d: -f1 | tr -d '\r') || { echo "ERROR: Failed to get rds_endpoint"; exit 1; }
NOTIFY_API_URL=$("$TERRAFORM" -chdir="$BACKEND_DIR" output -raw notify_api_url | tr -d '\r') || { echo "ERROR: Failed to get notify_api_url"; exit 1; }
AWS_ACCOUNT_ID=$("$AWS" sts get-caller-identity --query Account --output text | tr -d '\r') || { echo "ERROR: Failed to get AWS account ID"; exit 1; }

echo "  RDS endpoint : $RDS_ENDPOINT"
echo "  Notify API   : $NOTIFY_API_URL"
echo "  Account ID   : $AWS_ACCOUNT_ID"

# =============================================================================
echo "=== [2/6] Updating kubeconfig for EKS ==="
"$AWS" eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION"

"$KUBECTL" cluster-info

# =============================================================================
echo "=== [3/6] Installing Istio ${ISTIO_VERSION} ==="

# Download istioctl if not present
ISTIOCTL=$(command -v istioctl 2>/dev/null || command -v istioctl.exe 2>/dev/null || echo "")
if [ -z "$ISTIOCTL" ]; then
  echo "  Downloading istioctl..."
  curl -sSL "https://istio.io/downloadIstio" | ISTIO_VERSION="$ISTIO_VERSION" sh -
  export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"
  ISTIOCTL="$PWD/istio-${ISTIO_VERSION}/bin/istioctl"
fi

# Install Istio with default profile
"$ISTIOCTL" install --set profile=default -y

# Wait for Istio control plane to be ready
echo "  Waiting for Istio control plane..."
"$KUBECTL" rollout status deployment/istiod -n istio-system --timeout=180s

# Apply custom Istio ingress gateway service (NLB)
"$KUBECTL" apply -f "$K8S_DIR/istio-ingress-service.yaml"

echo "  Waiting for Istio ingress gateway..."
"$KUBECTL" rollout status deployment/istio-ingressgateway -n istio-system --timeout=120s

# =============================================================================
echo "=== [4/6] Applying base Kubernetes resources ==="

# Namespace with istio-injection enabled
"$KUBECTL" apply -f "$K8S_DIR/namespace.yaml"

# ConfigMap — inject actual RDS endpoint from Terraform output
sed "s|DB_HOST: .*|DB_HOST: \"$RDS_ENDPOINT\"|" "$K8S_DIR/configmap.yaml" | \
  "$KUBECTL" apply -f -

# Kafka and Redis (supporting services)
"$KUBECTL" apply -f "$K8S_DIR/kafka.yaml"
"$KUBECTL" apply -f "$K8S_DIR/redis.yaml"

# Wait for supporting services
echo "  Waiting for Redis..."
"$KUBECTL" rollout status deployment/redis -n soiree --timeout=120s || true

# =============================================================================
echo "=== [5/6] Building and pushing Docker images to ECR ==="

ECR_AUTH_URL="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Authenticate Docker to ECR
"$AWS" ecr get-login-password --region "$AWS_REGION" | \
  "$DOCKER" login --username AWS --password-stdin "$ECR_AUTH_URL"

build_and_push() {
  local SERVICE="$1"
  local CONTEXT="$2"
  local ECR_REPO="$3"
  echo "  Building $SERVICE..."
  "$DOCKER" build -t "$SERVICE:latest" "$CONTEXT"
  "$DOCKER" tag "$SERVICE:latest" "$ECR_REPO:latest"
  "$DOCKER" push "$ECR_REPO:latest"
}

build_and_push "auth-service"   "services/auth-service"   "$ECR_AUTH_URL/soiree/auth-service"
build_and_push "event-service"  "services/event-service"  "$ECR_AUTH_URL/soiree/event-service"
build_and_push "rsvp-service"   "services/rsvp-service"   "$ECR_AUTH_URL/soiree/rsvp-service"
build_and_push "frontend"       "frontend"                "$ECR_AUTH_URL/soiree/frontend"

# Replace placeholder account ID in manifests and deploy
for MANIFEST in auth-service.yaml event-service.yaml rsvp-service.yaml frontend.yaml; do
  sed "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" "$K8S_DIR/$MANIFEST" | \
    "$KUBECTL" apply -f -
done

# Wait for all deployments to roll out
for DEP in auth-service event-service rsvp-service frontend; do
  echo "  Waiting for $DEP..."
  "$KUBECTL" rollout status deployment/$DEP -n soiree --timeout=180s
done

# =============================================================================
echo "=== [6/6] Applying Istio traffic management ==="

"$KUBECTL" apply -f "$K8S_DIR/istio-peerauthentication.yaml"
"$KUBECTL" apply -f "$K8S_DIR/istio-gateway.yaml"
"$KUBECTL" apply -f "$K8S_DIR/istio-virtualservice.yaml"
"$KUBECTL" apply -f "$K8S_DIR/istio-destinationrules.yaml"

# =============================================================================
echo ""
echo "=== Deployment complete! ==="
echo ""

NLB_HOST=$("$KUBECTL" get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo "  Istio NLB hostname : $NLB_HOST"
echo "  Namespace          : soiree"
echo ""
echo "  Monitoring (access via kubectl port-forward):"
echo "    Prometheus : kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
echo "    Grafana    : kubectl port-forward svc/grafana 3000:3000 -n monitoring  (admin / SoireeGrafana2026!)"
echo "    Splunk     : kubectl port-forward svc/splunk 8000:8000 -n monitoring   (admin / SoireeSplunk2026!)"
echo ""
echo "  Next steps:"
echo "  1. Point dieunga.io.vn → $NLB_HOST in Route53 (or run: bash k8s/update-route53.sh)"
echo "  2. Verify services:  kubectl get pods -n soiree"
echo "  3. Verify Istio:     kubectl get pods -n istio-system"
echo "  4. Check mTLS:       $ISTIOCTL authn tls-check -n soiree"
