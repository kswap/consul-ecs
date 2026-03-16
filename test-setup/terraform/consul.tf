data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_key_pair" "consul" {
  key_name   = "consul-ecs-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_instance" "consul" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type_consul
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.consul.id]
  key_name                    = aws_key_pair.consul.key_name
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install dependencies
    yum install -y unzip curl jq

    # Download and install Consul
    curl -fsSL "https://releases.hashicorp.com/consul/${var.consul_version}/consul_${var.consul_version}_linux_amd64.zip" \
      -o /tmp/consul.zip
    unzip /tmp/consul.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/consul

    # Create Consul user and directories
    useradd --system --home /etc/consul.d --shell /bin/false consul
    mkdir -p /etc/consul.d /var/lib/consul
    chown -R consul:consul /etc/consul.d /var/lib/consul

    # Write Consul config (initial_management token pre-set by Terraform)
    cat > /etc/consul.d/consul.hcl <<CONSULCONFIG
datacenter = "dc1"
data_dir   = "/var/lib/consul"
server     = true
bootstrap_expect = 1
bind_addr  = "0.0.0.0"
advertise_addr = "{{ GetPrivateIP }}"
client_addr = "0.0.0.0"
ports {
  grpc = 8502
}
acl {
  enabled                  = true
  default_policy           = "deny"
  enable_token_persistence = true
  tokens {
    initial_management = "${random_uuid.consul_token.result}"
  }
}
CONSULCONFIG

    chown consul:consul /etc/consul.d/consul.hcl

    # Create systemd service
    cat > /etc/systemd/system/consul.service <<'SYSTEMD'
[Unit]
Description=Consul Agent
Wants=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SYSTEMD

    systemctl daemon-reload
    systemctl enable consul
    systemctl start consul
  EOF

  tags = { Name = "consul-server" }
}
