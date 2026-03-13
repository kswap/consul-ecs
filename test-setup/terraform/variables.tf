variable "region" {
  default = "ap-south-1"
}

variable "your_ip_cidr" {
  description = "Your public IP in CIDR notation, e.g. 1.2.3.4/32"
}

variable "consul_version" {
  default = "1.22.0"
}

variable "consul_token" {
  description = "Consul bootstrap management token (set after running bootstrap_consul.sh)"
  sensitive   = true
  default     = ""
}

variable "instance_type_consul" {
  default = "t3.small"
}

variable "instance_type_ecs" {
  default = "t3.medium"
}
