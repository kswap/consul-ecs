resource "aws_security_group" "consul" {
  name        = "consul-server-sg"
  description = "Security group for Consul EC2 server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  ingress {
    description     = "Server RPC from ECS tasks"
    from_port       = 8300
    to_port         = 8300
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "Serf LAN TCP from ECS tasks"
    from_port       = 8301
    to_port         = 8301
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "Serf LAN UDP from ECS tasks"
    from_port       = 8301
    to_port         = 8301
    protocol        = "udp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "HTTP API from ECS tasks"
    from_port       = 8500
    to_port         = 8500
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description = "HTTP API from operator"
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  ingress {
    description     = "gRPC (consul-dataplane) from ECS tasks"
    from_port       = 8502
    to_port         = 8502
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "consul-server-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Security group for ECS task containers"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "ecs-tasks-sg" }
}

resource "aws_security_group_rule" "ecs_tasks_self" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.ecs_tasks.id
  security_group_id        = aws_security_group.ecs_tasks.id
  description              = "Intra-task communication"
}

resource "aws_security_group_rule" "ecs_tasks_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Outbound to Consul, DockerHub, ECR"
}
