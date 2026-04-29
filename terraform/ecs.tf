########################################
# ECS Fargate Cluster + AI Agent Service
# Replaces EKS (blocked by SCP in sandbox)
########################################

# ---- ECR Repository for AI Agent ----
resource "aws_ecr_repository" "agent" {
  name                 = "redis-agent-platform"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

# ---- ECS Fargate Cluster ----
resource "aws_ecs_cluster" "main" {
  name = "redis-agent-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

# ---- IAM Role for ECS Task Execution ----
resource "aws_iam_role" "ecs_task_execution" {
  name = "redis-agent-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ---- IAM Role for ECS Task (Bedrock access) ----
resource "aws_iam_role" "ecs_task" {
  name = "redis-agent-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_access" {
  name = "bedrock-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "bedrock:InvokeModel", 
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:GetFoundationModel",
        "bedrock:ListFoundationModels"
      ]
      Resource = "*"
    },
    {
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:DescribeFileSystems"
      ]
      Resource = aws_efs_file_system.redis.arn
    }]
  })
}

# ---- Security Group for ECS Tasks ----
resource "aws_security_group" "ecs_tasks" {
  name        = "redis-agent-ecs-sg"
  description = "Allow inbound traffic to ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

# ---- Security Group for ALB ----
resource "aws_security_group" "alb" {
  name        = "redis-agent-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

# ---- Application Load Balancer ----
resource "aws_lb" "main" {
  name               = "redis-agent-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

resource "aws_lb_target_group" "agent" {
  name        = "redis-agent-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent.arn
  }
}

# ---- CloudWatch Log Group ----
resource "aws_cloudwatch_log_group" "agent" {
  name              = "/ecs/redis-agent"
  retention_in_days = 7
}

# ---- ECS Task Definition ----
resource "aws_ecs_task_definition" "agent" {
  family                   = "redis-agent"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "redis-agent"
    image     = "${aws_ecr_repository.agent.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "aws_region", value = "us-east-1" },
      { name = "redis_host", value = "redis-0.redis.local" },
      { name = "redis_port", value = "6379" },
      { name = "redis_cluster_mode", value = "true" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.agent.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

# ---- ECS Fargate Service (HA with 2 replicas) ----
resource "aws_ecs_service" "agent" {
  name            = "redis-agent-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.agent.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  force_new_deployment = true

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.agent.arn
    container_name   = "redis-agent"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Environment = "prod"
    Project     = "redis-agent-platform"
  }
}

# ---- Auto Scaling for ECS Service ----
resource "aws_appautoscaling_target" "agent" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.agent.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "agent_cpu" {
  name               = "redis-agent-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.agent.resource_id
  scalable_dimension = aws_appautoscaling_target.agent.scalable_dimension
  service_namespace  = aws_appautoscaling_target.agent.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ---- EFS Persistence for Redis Cluster ----
resource "aws_efs_file_system" "redis" {
  creation_token = "redis-cluster-data"
  encrypted      = true

  tags = {
    Name    = "redis-cluster-storage"
    Project = "redis-agent-platform"
  }
}

# Mount Targets (one per subnet)
resource "aws_efs_mount_target" "redis" {
  count           = length(module.vpc.private_subnets)
  file_system_id  = aws_efs_file_system.redis.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# 6 Access Points (one for each node: 0-5)
resource "aws_efs_access_point" "redis" {
  count          = 6
  file_system_id = aws_efs_file_system.redis.id

  root_directory {
    path = "/redis-${count.index}"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
}

# ---- Service Discovery (Cloud Map) ----
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "redis.local"
  description = "Service discovery for Redis Cluster"
  vpc         = module.vpc.vpc_id
}

# 6 Discovery Services (redis-0.redis.local to redis-5.redis.local)
resource "aws_service_discovery_service" "redis" {
  count = 6
  name  = "redis-${count.index}"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

# ---- Security Groups ----
resource "aws_security_group" "efs" {
  name        = "redis-efs-sg"
  description = "Allow Redis nodes to talk to EFS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.redis_cluster.id]
  }
}

resource "aws_security_group" "redis_cluster" {
  name        = "redis-cluster-sg"
  description = "Redis Cluster data and bus traffic"
  vpc_id      = module.vpc.vpc_id

  # Data Port
  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    self        = true
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # Cluster Bus Port
  ingress {
    from_port   = 16379
    to_port     = 16379
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---- Redis Cluster Task Definition (Template) ----
resource "aws_ecs_task_definition" "redis" {
  count                    = 6
  family                   = "redis-node-${count.index}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "redis"
    image     = "redis:7-alpine"
    essential = true

    command = [
      "redis-server",
      "--cluster-enabled", "yes",
      "--cluster-config-file", "/data/nodes.conf",
      "--cluster-node-timeout", "5000",
      "--appendonly", "yes",
      "--protected-mode", "no",
      "--bind", "0.0.0.0"
    ]

    portMappings = [
      { containerPort = 6379, protocol = "tcp" },
      { containerPort = 16379, protocol = "tcp" }
    ]

    mountPoints = [{
      containerPath = "/data"
      sourceVolume  = "redis-data"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.agent.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "redis-${count.index}"
      }
    }
  }])

  volume {
    name = "redis-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.redis.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.redis[count.index].id
        iam             = "ENABLED"
      }
    }
  }
}

# ---- 6 Redis Services (Stable Identities) ----
resource "aws_ecs_service" "redis" {
  count           = 6
  name            = "redis-node-${count.index}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis[count.index].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.redis_cluster.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis[count.index].arn
  }
}

# ---- Disaster Recovery: AWS Backup ----
resource "aws_backup_vault" "redis" {
  name = "redis-backup-vault"
}

resource "aws_backup_plan" "redis" {
  name = "redis-dr-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.redis.name
    schedule          = "cron(0 5 * * ? *)" # 5 AM daily

    lifecycle {
      delete_after = 30
    }
  }
}

resource "aws_backup_selection" "redis" {
  iam_role_arn = aws_iam_role.ecs_task_execution.arn # Needs backup permissions
  name         = "redis-efs-selection"
  plan_id      = aws_backup_plan.redis.id

  resources = [
    aws_efs_file_system.redis.arn
  ]
}

# ---- Outputs ----
output "agent_url" {
  description = "Public URL of the AI Agent API"
  value       = "http://${aws_lb.main.dns_name}"
}

# ---- Cluster Bootstrap Task (Run once) ----
resource "aws_ecs_task_definition" "redis_bootstrap" {
  family                   = "redis-cluster-bootstrap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "bootstrap"
    image     = "redis:7-alpine"
    essential = true

    # This command creates the cluster with 1 replica per master (3 masters + 3 replicas = 6 nodes)
    command = [
      "sh", "-c",
      "redis-cli --cluster create redis-0.redis.local:6379 redis-1.redis.local:6379 redis-2.redis.local:6379 redis-3.redis.local:6379 redis-4.redis.local:6379 redis-5.redis.local:6379 --cluster-replicas 1 --cluster-yes"
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.agent.name
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "bootstrap"
      }
    }
  }])
}

output "redis_nodes" {
  description = "DNS names of the Redis cluster nodes"
  value       = [for i in range(6) : "redis-${i}.redis.local:6379"]
}

output "bootstrap_task_family" {
  value = aws_ecs_task_definition.redis_bootstrap.family
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "redis_cluster_sg_id" {
  value = aws_security_group.redis_cluster.id
}
