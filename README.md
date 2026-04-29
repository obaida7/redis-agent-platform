# 🤖 Agentic Redis SRE Platform (Serverless)

[![Build and Deploy](https://github.com/obaida7/redis-agent-platform/actions/workflows/deploy.yaml/badge.svg)](https://github.com/obaida7/redis-agent-platform/actions/workflows/deploy.yaml)

A production-grade **Agentic AI SRE Control Plane** designed to automate the operational management of Redis infrastructure. This platform utilizes **Claude 4.6 Sonnet** and **LangGraph** to autonomously diagnose, scale, and heal Redis environments using natural language reasoning.

## 🏗️ Architecture: Serverless & Elastic

This project has been migrated to a fully **Serverless AWS Architecture** to ensure high availability, zero-maintenance overhead, and rapid deployment.

1.  **AI Control Plane**: A Python FastAPI backend running as an **ECS Fargate** service. It uses **LangGraph** for cyclic reasoning and **AWS Bedrock** as the brain.
2.  **Infrastructure-as-Code**: A bulletproof **Terraform** stack that provisions a custom VPC, ECS Cluster, Application Load Balancer (ALB), and ECR Registry.
3.  **Self-Healing CI/CD**: A "Zero-Touch" GitHub Actions pipeline that automatically bootstraps the S3 state backend and DynamoDB locking in any clean AWS account.

---

## 🚀 "Zero-Touch" Deployment

This platform is designed to be deployed into a completely empty AWS account with a single push.

### 1. Prerequisites
- AWS Access Keys with Administrator access.
- A GitHub repository with the following secrets configured:
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `AWS_SESSION_TOKEN` (if using temporary credentials)

### 2. Automatic Bootstrap
The pipeline (`.github/workflows/deploy.yaml`) is self-healing. It will:
- Detect if the S3 state bucket exists; if not, it creates it.
- Detect if the DynamoDB lock table exists; if not, it creates it.
- Provision the ECR registry before the first Docker build.

### 3. Deploy
Simply push to the `main` branch. The pipeline will:
1. Build the AI Agent Docker image.
2. Push it to ECR.
3. Provision the VPC and ECS Cluster via Terraform.
4. Launch the Agent as an HA Fargate service (2 replicas across AZs).

---

## 🛠️ SRE Toolset (AI-Powered)

The AI Agent is equipped with specialized tools to manage Redis infrastructure:

-   **Health & Performance**: `check_redis_health` monitors memory usage, CPU, and connected clients.
-   **Traffic Management**: `detect_noisy_neighbor` identifies abusive clients based on ops/sec.
-   **Incident Response**: `mitigate_noisy_neighbor` disconnects abusive clients automatically.
-   **Performance Optimization**: `detect_cache_stampede` and `apply_jitter_or_lock` mitigate thundering herd problems.
-   **Elasticity**: `scale_redis_replicas` (ready for integration with your Redis cluster).

---

## 🧪 Testing the Platform

Once the pipeline completes, Terraform will output the `agent_url`.

### Health Check
```bash
curl http://<YOUR_ALB_URL>/health
```

### Chat with the SRE Agent
Ask the agent to perform an audit or solve a problem:
```bash
curl -X POST http://<YOUR_ALB_URL>/api/v1/chat \
     -H "Content-Type: application/json" \
     -d '{"message": "Audit the memory usage of my Redis cluster and look for any noisy neighbors."}'
```

---

## 🛡️ Security & Scalability
-   **IAM Roles**: The ECS tasks use a dedicated Task Role with least-privilege access to AWS Bedrock.
-   **Networking**: Tasks run in **Private Subnets**. Only the ALB is public-facing.
-   **Auto-Scaling**: The ECS service automatically scales from **2 to 10 tasks** based on CPU utilization (target 70%).
-   **State Safety**: Terraform uses S3 with DynamoDB state locking to ensure multi-engineer safety.

## 🧰 Tech Stack
-   **Brain**: AWS Bedrock (Claude 4.6 Sonnet)
-   **Logic**: LangGraph / LangChain
-   **API**: FastAPI (Python 3.10)
-   **Infrastructure**: Terraform 1.9
-   **Compute**: AWS ECS Fargate
-   **CI/CD**: GitHub Actions
