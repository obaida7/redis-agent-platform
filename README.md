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
* [Docker](https://docs.docker.com/get-docker/) & [Kind](https://kind.sigs.k8s.io/) (for local Kubernetes)
* `kubectl`
* Python 3.10+
* AWS CLI configured with Bedrock access (`aws configure`)

### 1. Deploy the Infrastructure

First, spin up a local Kubernetes cluster and deploy the Redis Enterprise Operator:

```bash
kind create cluster --name redis-prod-cluster
kubectl create namespace redis

# Apply the Redis Operator, Cluster, and Database
kubectl apply -f infrastructure/bundle.yaml
kubectl apply -f infrastructure/redis-app-secret.yaml
kubectl apply -f infrastructure/redis-enterprise-cluster.yaml
kubectl apply -f infrastructure/redis-database.yaml
kubectl apply -f infrastructure/redis-service.yaml
```

Wait for the operator to provision the database. You can check the status and grab the dynamic port with:
```bash
kubectl get redb prod-db -n redis
```

### 2. Setup the AI Control Plane

Set up your Python virtual environment and install the dependencies:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Create a `.env` file in the root directory:
```env
aws_region=us-east-1
redis_password=YOUR_GENERATED_PASSWORD
redis_port=YOUR_GENERATED_PORT
```
*(Note: You can get the generated password using: `kubectl get secret redb-prod-db -n redis -o jsonpath="{.data.password}" | base64 --decode`)*

### 3. Expose Redis Locally
In a separate terminal, forward the dynamic database port to your local machine:
```bash
kubectl port-forward svc/prod-db <YOUR_PORT>:<YOUR_PORT> -n redis
```

### 4. Run the Agentic Platform
Start the FastAPI server:
```bash
./run.sh
```

Navigate to **http://localhost:8000/docs** in your browser. Use the `/api/v1/chat` endpoint and ask the SRE agent a question like:
> *"Can you check the health of the Redis database and verify if the Kubernetes pods are stable?"*

## 🛠️ Built With
* **Python / FastAPI**
* **LangGraph / LangChain** (AI Orchestration)
* **AWS Bedrock (Claude 3.7 Sonnet)**
* **Redis Enterprise Operator** (Kubernetes CRDs)
* **boto3, redis-py, kubernetes client**
