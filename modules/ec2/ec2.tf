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
set -eux

### -------------------------
### 1. Ensure ubuntu user password REALLY works (passwd-style)
### -------------------------
echo "ubuntu:ubuntu" | chpasswd
passwd -u ubuntu || true
chage -E -1 ubuntu || true

### -------------------------
### 2. SSH key (needed for Jenkins / Ansible)
### -------------------------
mkdir -p /home/ubuntu/.ssh
cat <<EOF > /home/ubuntu/.ssh/authorized_keys
${var.public_key}
EOF
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

systemctl enable ssh --now

### -------------------------
### 3. Force DCV PAM authentication
### -------------------------
mkdir -p /etc/dcv
cat <<EOF > /etc/dcv/dcv.conf
[authentication]
pam-authentication=true
EOF

### -------------------------
### 4. Restart DCV so PAM + password are loaded
### -------------------------
systemctl restart dcvserver
sleep 5

### -------------------------
### 5. Create DCV session automatically
### -------------------------
dcv create-session desktop --owner ubuntu || true

### -------------------------
### 6. Enable DCV at boot
### -------------------------
systemctl enable dcvserver

echo "DCV READY"
EOT


  lifecycle { ignore_changes = [user_data] }
}
