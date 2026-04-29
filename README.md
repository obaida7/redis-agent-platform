# Agentic Redis SRE Platform

This project is a production-grade **Agentic AI SRE Control Plane** built to automate the operational management of a Highly Available Redis Enterprise cluster on Kubernetes. 

It was designed to demonstrate advanced Platform Engineering, combining declarative Infrastructure-as-Code (IaC) with cyclic LLM reasoning (LangGraph + AWS Bedrock) to perform automated Root Cause Analysis (RCA) and remediation on a massive scale.

## 🏗️ Architecture

The architecture is divided into two layers:
1. **Infrastructure (`/infrastructure`)**: Kubernetes manifests that deploy the official Redis Enterprise Operator, spinning up a 3-node Highly Available cluster and a logical database.
2. **Control Plane (`/`)**: A Python FastAPI backend orchestrating a LangGraph AI Agent. The agent is equipped with custom tools using `redis-py` and the `kubernetes` Python SDK to autonomously diagnose and heal the cluster.

---

## 🚀 Getting Started

### Prerequisites
* AWS CLI configured (`aws configure`) with Bedrock and EKS access
* `kubectl` configured with your EKS cluster context (`aws eks update-kubeconfig ...`)
* Python 3.10+

### 1. Provision the EKS Cluster (Terraform)

First, use the provided Terraform configuration to provision the VPC, EKS cluster, and Node Groups in AWS.

```bash
cd terraform
terraform init
terraform apply
```

After the cluster is provisioned, configure your local `kubectl` to connect to it:

```bash
aws eks update-kubeconfig --region us-east-1 --name redis-prod-cluster
cd ..
```

### 2. GitOps Deployment (ArgoCD)

The infrastructure deployment is completely "Zero-Touch". When Terraform finishes provisioning the EKS cluster, it automatically installs ArgoCD via Helm and applies the GitOps Application manifest.

ArgoCD will automatically sync and deploy the Redis Operator, Cluster, Database, and monitoring stack from this Git repository.

### 3. Setup the AI Control Plane (CI Pipeline)

This project includes a **GitHub Actions CI Pipeline** (`.github/workflows/ci.yaml`) and a `Dockerfile` that automatically tests and builds the Python Agentic AI backend whenever code is pushed to `main`.

Create a `.env` file in the root directory:
```env
aws_region=us-east-1
redis_password=YOUR_GENERATED_PASSWORD
redis_port=YOUR_GENERATED_PORT
```
*(Note: You can get the generated password using: `kubectl get secret redb-prod-db -n redis -o jsonpath="{.data.password}" | base64 --decode`)*

### 4. Connect to the Control Plane
Since this is running in EKS, ensure you are running the agent from an environment that has network access to the EKS cluster's VPC, or set up appropriate ingress/port-forwarding for development:
```bash
kubectl port-forward svc/prod-db 19999:19999 -n redis
```

### 4. Run the Agentic Platform

Because the infrastructure is deployed in EKS and containerized, the AI agent can be deployed to the cluster or run as a container natively.
Make sure you provide the agent container with the correct IAM roles to call Bedrock, and pass the Redis connection string via environment variables.

Navigate to your deployed API's `/docs` endpoint in your browser. Use the `/api/v1/chat` endpoint and ask the SRE agent a question like:
> *"Can you check the health of the Redis database and verify if the Kubernetes pods are stable?"*

## 🛠️ Built With
* **Python / FastAPI**
* **LangGraph / LangChain** (AI Orchestration)
* **AWS Bedrock (Claude 3.7 Sonnet)**
* **Redis Enterprise Operator** (Kubernetes CRDs)
* **boto3, redis-py, kubernetes client**
