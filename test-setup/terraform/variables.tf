variable "region" {
  default = "ap-south-1"
}

variable "consul_version" {
  default = "1.22.0"
}

variable "instance_type_consul" {
  default = "t3.small"
}

variable "instance_type_ecs" {
  default = "t3.medium"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key for the Consul EC2 instance"
  default     = "~/.ssh/consul-ecs.pub"
}
