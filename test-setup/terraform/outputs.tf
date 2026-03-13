output "consul_server_ip" {
  description = "Public IP of the Consul server EC2 instance"
  value       = aws_instance.consul.public_ip
}

output "consul_private_ip" {
  description = "Private IP of the Consul server EC2 instance"
  value       = aws_instance.consul.private_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL for the consul-ecs image"
  value       = aws_ecr_repository.consul_ecs.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.test.name
}

output "region" {
  description = "AWS region"
  value       = var.region
}
