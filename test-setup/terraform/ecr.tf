resource "aws_ecr_repository" "consul_ecs" {
  name                 = "consul-ecs"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "consul-ecs" }
}
