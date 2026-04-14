#!/bin/bash
# Update Route53 to point domain to Istio NLB
# Run after deploy.sh when NLB is fully provisioned
set -e

DOMAIN="dieunga.io.vn"
AWS_REGION="ap-southeast-1"

echo "=== Updating Route53 for $DOMAIN ==="

cd "$(dirname "${BASH_SOURCE[0]}")/../backend"
ZONE_ID=$(terraform output -raw route53_zone_id)

NLB_HOST=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$NLB_HOST" ]; then
  echo "ERROR: NLB hostname not available yet. Wait a few minutes and retry."
  exit 1
fi

echo "  Zone ID    : $ZONE_ID"
echo "  NLB host   : $NLB_HOST"

# Get the hosted zone ID of the NLB (needed for alias record)
NLB_ZONE=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query "LoadBalancers[?DNSName=='$NLB_HOST'].CanonicalHostedZoneId" \
  --output text)

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DOMAIN\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$NLB_ZONE\",
          \"DNSName\": \"$NLB_HOST\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }"

echo "=== Route53 updated. DNS propagation may take 1-5 minutes. ==="
