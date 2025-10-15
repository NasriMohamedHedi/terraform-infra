resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "EC2CloudWatchRole-${random_id.unique_suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
  name = "EC2CloudWatchProfile-${random_id.unique_suffix.hex}"
  role = aws_iam_role.ec2_cloudwatch_role.name
}

resource "random_id" "unique_suffix" {
  byte_length = 4
}

resource "aws_instance" "this" {
  for_each = var.instances

  ami           = each.value.ami
  instance_type = each.value.instance_type
  key_name      = var.key_name
  vpc_security_group_ids = [var.security_group_id]
  subnet_id     = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.ec2_cloudwatch_profile.name

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
    echo "${var.public_key}" > /home/ubuntu/.ssh/authorized_keys
    
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
