resource "aws_cloudwatch_log_group" "consul_ecs" {
  name              = "/consul-ecs/test"
  retention_in_days = 7

  tags = { Name = "consul-ecs-logs" }
}
