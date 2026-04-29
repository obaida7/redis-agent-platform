# 🤖 Agentic Redis SRE Platform (Enterprise Sharded)

[![Build and Deploy](https://github.com/obaida7/redis-agent-platform/actions/workflows/deploy.yaml/badge.svg)](https://github.com/obaida7/redis-agent-platform/actions/workflows/deploy.yaml)

A production-grade **Agentic AI SRE Control Plane** designed to automate the operational management of distributed Redis infrastructure. This platform utilizes **Claude 3 Haiku** and **LangGraph** to autonomously diagnose, shard, and heal a multi-node Redis cluster.

## 🏗️ Architecture: Distributed & Resilient

The platform has been engineered for "Enterprise-Grade" stability in a serverless environment:

1.  **Sharded Redis Cluster**: A 6-node topology (3 Masters + 3 Replicas) providing high availability and horizontal scaling across 3 Availability Zones.
2.  **Stateful Fargate Persistence**: Utilizes **AWS EFS (Elastic File System)** with dedicated access points per node. This ensures that cluster identity and data (AOF) persist even across container restarts.
3.  **Disaster Recovery (DR)**: Integrated with **AWS Backup** for automated, daily snapshots of the entire Redis storage layer with a 30-day retention policy.
4.  **Self-Healing Bootstrap**: A custom "Cluster Orchestrator" in the CI/CD pipeline that handles DNS propagation waits, node resets, and automated sharding.

---

## 🛠️ SRE Toolset (Cluster-Aware)

The AI Agent is equipped with specialized tools designed for distributed environments:

-   **Topology Audit**: `get_cluster_nodes` scans all 6 shards to verify master/replica health and slot coverage.
-   **Distributed Noisy Neighbor**: `detect_noisy_neighbor` iterates across all 3 masters to find and disconnect abusive clients cluster-wide.
-   **Cache Stampede Mitigation**: Identifies hot keys and applies probabilistic jitter to prevent backend thundering herds.
-   **Auto-Remediation**: The agent performs autonomous Root Cause Analysis (RCA) and can execute hard resets or sharding repairs if it detects an unhealthy cluster state.

---

## 🚀 "Zero-Touch" Deployment

The platform is designed to be deployed into a completely empty AWS account with a single push.

### 1. Prerequisites
- AWS Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) configured in GitHub.

### 2. Automatic Lifecycle
The pipeline (`.github/workflows/deploy.yaml`) handles the entire infrastructure lifecycle:
- Provisions VPC, ECR, ECS, EFS, and AWS Backup via **Terraform**.
- Builds and pushes the AI Agent image.
- **Triggers a Bootstrap Task** to perform the initial cluster handshake once nodes are healthy.

---

## 🧪 Testing the Platform

Ask the SRE Agent to perform an audit or solve a problem:

### Cluster Health Audit
```bash
curl -X POST http://<YOUR_ALB_URL>/api/v1/chat \
     -H "Content-Type: application/json" \
     -d '{"message": "Audit the sharding state. List all 6 nodes and confirm if all 16384 slots are covered."}'
```

### Noisy Neighbor Detection
```bash
curl -X POST http://<YOUR_ALB_URL>/api/v1/chat \
     -H "Content-Type: application/json" \
     -d '{"message": "Scan all cluster masters for noisy neighbors consuming more than 10MB of memory."}'
```

---

## 🛡️ Security & Scalability
-   **IAM Authorization**: EFS mounts are secured via IAM, requiring specific ECS Task Roles.
-   **Network Isolation**: All Redis nodes run in **Private Subnets**. Communication is handled via **AWS Cloud Map** (Private DNS).
-   **Auto-Scaling**: The AI Control Plane scales horizontally (2 to 10 tasks) based on CPU utilization.
