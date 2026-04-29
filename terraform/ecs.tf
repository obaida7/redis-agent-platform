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
      { name = "redis_port", value = "19999" }
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

# ---- Outputs ----
output "agent_url" {
  description = "Public URL of the AI Agent API"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR Repository URL for the AI Agent"
  value       = aws_ecr_repository.agent.repository_url
}
