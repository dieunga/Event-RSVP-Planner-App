# Soirée — Event RSVP Planner (Microservices)

🎥 **[Watch Demo Video](https://buveduvn0-my.sharepoint.com/personal/nga_nd_st_buv_edu_vn/_layouts/15/guestaccess.aspx?share=IQAAG8J22veVTLcJuZm6h1IUAXc1RA7scl2uOnczqZGXN5o&e=Nt6Cg2)**

A cloud-native event management application built with microservices architecture, deployed on AWS EKS with Istio service mesh.

## Architecture Overview

```
Internet → Route 53 → NLB (Internet-facing) → Istio Ingress Gateway
                                                      ↓
                                              ┌── Frontend (Nginx)
                                              ├── Auth Service (Node.js)
                                              ├── Event Service (Node.js)
                                              └── RSVP Service (Node.js)
                                                      ↓
                                      ┌── AWS RDS (MySQL) ──┐
                                      ├── Redis (Sessions/Cache)
                                      └── Kafka (Event Messaging)
```

## Requirements Checklist

| Requirement | Status | Implementation |
|---|---|---|
| Local app (Node.js) | Done | 3 Node.js microservices + Nginx frontend |
| AWS RDS | Done | MySQL 8.0 on `db.t3.micro` |
| AWS EKS deployment | Done | EKS cluster with managed node groups |
| K8s YAML configs | Done | Full manifests in `k8s/` directory |
| Istio service mesh | Done | Gateway, VirtualService, DestinationRules, mTLS |
| Internet-facing LB | Done | NLB via Istio Ingress Gateway |
| Route 53 access | Done | A-record alias to NLB |
| CI/CD pipeline | Done | GitHub Actions (build → push → deploy) |
| Terraform (IaC) | Done | EKS, VPC, RDS, ECR, IAM, Route53 |
| Kafka | Done | Confluent Kafka on K8s for event messaging |
| Redis | Done | Redis for session storage and caching |

## Project Structure

```
├── .github/workflows/
│   └── ci-cd.yaml              # GitHub Actions CI/CD pipeline
├── backend/                     # Terraform infrastructure (IaC)
│   ├── providers.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── main.tf                 # VPC, Subnets, Route53
│   ├── eks.tf                  # EKS Cluster, Node Groups, ECR
│   ├── database.tf             # RDS MySQL
│   ├── routing.tf              # NAT Gateways, Route Tables
│   ├── securityahh.tf          # Security Groups
│   └── autoscaling.tf          # Outputs
├── services/                    # Backend microservices
│   ├── auth-service/           # Authentication (port 3001)
│   │   ├── server.js
│   │   ├── package.json
│   │   └── Dockerfile
│   ├── event-service/          # Event CRUD (port 3002)
│   │   ├── server.js
│   │   ├── package.json
│   │   └── Dockerfile
│   └── rsvp-service/           # RSVP management (port 3003)
│       ├── server.js
│       ├── package.json
│       └── Dockerfile
├── frontend/                    # Static frontend (Nginx)
│   ├── index.html
│   ├── login.html
│   ├── signup.html
│   ├── app.js
│   ├── styles.css
│   ├── nginx.conf
│   └── Dockerfile
└── k8s/                         # Kubernetes manifests
    ├── namespace.yaml
    ├── configmap.yaml
    ├── auth-service.yaml
    ├── event-service.yaml
    ├── rsvp-service.yaml
    ├── frontend.yaml
    ├── redis.yaml
    ├── kafka.yaml
    ├── istio-gateway.yaml
    ├── istio-virtualservice.yaml
    ├── istio-destinationrules.yaml
    ├── istio-peerauthentication.yaml
    └── istio-ingress-service.yaml
```

## Microservices

| Service | Port | Description | Kafka Topics |
|---|---|---|---|
| **auth-service** | 3001 | User signup/login, session management via Redis | `user-registered`, `user-login` |
| **event-service** | 3002 | CRUD operations for events, Redis caching | `event-created`, `event-updated`, `event-deleted` |
| **rsvp-service** | 3003 | RSVP management, listens for event deletions | `rsvp-created`, `rsvp-deleted` |
| **frontend** | 80 | Static Nginx serving HTML/CSS/JS | — |

## Deployment Guide

### Prerequisites

- AWS CLI configured
- Terraform >= 1.0
- kubectl
- Docker
- Istio CLI (`istioctl`)

### 1. Provision Infrastructure with Terraform

```bash
cd backend
terraform init
terraform plan
terraform apply
```

This creates: VPC, Subnets, EKS Cluster, RDS, ECR repos, Route53, IAM roles.

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --name soiree-eks-cluster --region ap-southeast-1
```

### 3. Install Istio

```bash
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled
```

### 4. Build & Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com

# Build and push each service
for svc in auth-service event-service rsvp-service; do
  docker build -t soiree/$svc services/$svc/
  docker tag soiree/$svc:latest <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/soiree/$svc:latest
  docker push <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/soiree/$svc:latest
done

# Build and push frontend
docker build -t soiree/frontend frontend/
docker tag soiree/frontend:latest <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/soiree/frontend:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/soiree/frontend:latest
```

### 5. Deploy to EKS

```bash
# Update image references in K8s manifests
sed -i 's/<AWS_ACCOUNT_ID>/YOUR_ACCOUNT_ID/g' k8s/*.yaml

# Update RDS endpoint in configmap
# Edit k8s/configmap.yaml → set DB_HOST to your RDS endpoint

# Apply manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/kafka.yaml
kubectl apply -f k8s/auth-service.yaml
kubectl apply -f k8s/event-service.yaml
kubectl apply -f k8s/rsvp-service.yaml
kubectl apply -f k8s/frontend.yaml

# Apply Istio configs
kubectl apply -f k8s/istio-gateway.yaml
kubectl apply -f k8s/istio-virtualservice.yaml
kubectl apply -f k8s/istio-destinationrules.yaml
kubectl apply -f k8s/istio-peerauthentication.yaml
kubectl apply -f k8s/istio-ingress-service.yaml
```

### 6. Verify

```bash
kubectl get pods -n soiree
kubectl get svc -n soiree
kubectl get svc istio-ingressgateway -n istio-system
```

## CI/CD Pipeline

GitHub Actions pipeline (`.github/workflows/ci-cd.yaml`) automates:

1. **Build & Test** — Install dependencies for each service
2. **Docker Build & Push** — Build images and push to ECR
3. **Deploy** — Apply K8s manifests to EKS cluster

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key |
| `AWS_ACCOUNT_ID` | AWS account ID for ECR |

## API Endpoints

### Auth Service
- `POST /api/auth/signup` — Register new user
- `POST /api/auth/login` — Login and get session token
- `POST /api/auth/logout` — Invalidate session
- `GET /api/auth/validate` — Validate session token

### Event Service
- `GET /api/events` — List user's events
- `GET /api/events/:id` — Get single event
- `POST /api/events` — Create event
- `PUT /api/events/:id` — Update event
- `DELETE /api/events/:id` — Delete event

### RSVP Service
- `GET /api/rsvps` — List all RSVPs
- `GET /api/rsvps/event/:eventId` — Get RSVPs for event
- `POST /api/rsvps` — Create RSVP
- `PUT /api/rsvps/:id` — Update RSVP
- `DELETE /api/rsvps/:id` — Delete RSVP