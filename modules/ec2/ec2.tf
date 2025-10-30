resource "random_id" "unique_suffix" {
  byte_length = 4
}

resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "EC2CloudWatchRole-${random_id.unique_suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
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

resource "aws_instance" "this" {
  for_each = var.instances

  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = var.security_groups
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.ec2_cloudwatch_profile.name
  associate_public_ip_address = true

  tags = merge(
    { Name = each.value.name },
    lookup(each.value, "tags", {})
  )

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /home/ubuntu/.ssh
    echo "${var.public_key}" > /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    chown ubuntu:ubuntu /home/ubuntu/.ssh -R
    systemctl enable ssh --now
    sleep 180
  EOT

  lifecycle { ignore_changes = [user_data] }
}
