data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_ecr" {
  name = "ecr-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      Resource = "*"
    }]
  })
}

# Task Role (for consul-ecs containers)
resource "aws_iam_role" "consul_ecs_task" {
  name               = "consul-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy" "consul_ecs_task_ecs" {
  name = "ecs-describe-tasks"
  role = aws_iam_role.consul_ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
        ]
        Resource = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      }
    ]
  })
}

# EC2 Instance Profile for ECS container instances
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_instance" {
  name               = "ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance_managed" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}
