locals {
  consul_ecs_config = templatefile("${path.module}/templates/consul_ecs_config.json.tpl", {
    consul_private_ip = aws_instance.consul.private_ip
  })
}

resource "aws_ecs_task_definition" "test" {
  family                   = "consul-ecs-test"
  network_mode             = "bridge"
  task_role_arn            = aws_iam_role.consul_ecs_task.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  volume {
    name = "consul-data"
  }

  container_definitions = jsonencode([
    {
      name      = "mesh-init"
      image     = "${aws_ecr_repository.consul_ecs.repository_url}:latest"
      command   = ["mesh-init"]
      essential = false

      environment = [
        { name = "CONSUL_ECS_CONFIG_JSON", value = local.consul_ecs_config },
        { name = "CONSUL_HTTP_TOKEN", value = var.consul_token },
      ]

      mountPoints = [
        { sourceVolume = "consul-data", containerPath = "/consul" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.consul_ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "mesh-init"
        }
      }
    },
    {
      name      = "consul-dataplane"
      image     = "hashicorp/consul-dataplane:1.6.3"
      essential = true

      command = ["-config-file=/consul/consul-dataplane.json"]

      dependsOn = [
        { containerName = "mesh-init", condition = "SUCCESS" }
      ]

      mountPoints = [
        { sourceVolume = "consul-data", containerPath = "/consul" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.consul_ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "consul-dataplane"
        }
      }
    },
    {
      name      = "health-sync"
      image     = "${aws_ecr_repository.consul_ecs.repository_url}:latest"
      command   = ["health-sync"]
      essential = false

      environment = [
        { name = "CONSUL_ECS_CONFIG_JSON", value = local.consul_ecs_config },
        { name = "CONSUL_HTTP_TOKEN", value = var.consul_token },
      ]

      dependsOn = [
        { containerName = "mesh-init", condition = "SUCCESS" }
      ]

      mountPoints = [
        { sourceVolume = "consul-data", containerPath = "/consul" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.consul_ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "health-sync"
        }
      }
    },
    {
      name      = "app"
      image     = "hashicorp/http-echo:latest"
      essential = true

      command = ["-text=hello"]

      portMappings = [
        { containerPort = 5678, hostPort = 0, protocol = "tcp" }
      ]

      healthCheck = {
        command     = ["CMD", "sh", "-c", "wget -qO- http://localhost:5678/ || exit 1"]
        interval    = 5
        timeout     = 3
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.consul_ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = { Name = "consul-ecs-test" }
}

resource "aws_ecs_service" "test" {
  name            = "consul-ecs-test"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.test.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  tags = { Name = "consul-ecs-test" }

  depends_on = [aws_ecs_cluster_capacity_providers.main]
}
