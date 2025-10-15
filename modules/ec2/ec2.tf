resource "tls_private_key" "ec2_key" {
  count     = 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key_pair" {
  count      = 1
  key_name   = "${var.key_name}-${random_id.unique_suffix[0].hex}"
  public_key = tls_private_key.ec2_key[0].public_key_openssh
}

resource "random_id" "unique_suffix" {
  count       = 1
  byte_length = 4
}

resource "aws_instance" "this" {
  for_each = var.instances

  ami           = each.value.ami
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.ec2_key_pair[0].key_name
  vpc_security_group_ids = [var.security_group_id]
  subnet_id     = var.subnet_id

  associate_public_ip_address = true

  tags = merge(
    {
      "Name"        = each.value.name
      "Environment" = "Development"
      "Owner"       = each.value.tags["Owner"]
    },
    each.value.tags
  )

  user_data = <<-EOT
    #!/bin/bash
    # Ensure .ssh directory exists and has proper permissions
    mkdir -p /home/ubuntu/.ssh
    chmod 700 /home/ubuntu/.ssh
    
    # Ensure authorized_keys file exists and has correct permissions
    if [ ! -f /home/ubuntu/.ssh/authorized_keys ]; then
      touch /home/ubuntu/.ssh/authorized_keys
    fi
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    
    # Copy the injected public key to authorized_keys
    echo "${tls_private_key.ec2_key[0].public_key_openssh}" > /home/ubuntu/.ssh/authorized_keys
    
    # Set ownership
    chown ubuntu:ubuntu /home/ubuntu/.ssh -R
    
    # Start and enable SSH service
    systemctl enable ssh --now
    
    # Wait longer to ensure SSH is fully ready
    sleep 180
  EOT

  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_security_group" "ec2_sg" {
  vpc_id = var.vpc_id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
