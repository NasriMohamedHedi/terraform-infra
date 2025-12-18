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
#cloud-config

# -------------------------
# 1️⃣ Enable password login for ubuntu
# -------------------------
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false

chpasswd:
  list: |
    ubuntu:ubuntu
  expire: False

ssh_pwauth: true

# -------------------------
# 2️⃣ SSH key for Ansible
# -------------------------
write_files:
  - path: /home/ubuntu/.ssh/authorized_keys
    owner: ubuntu:ubuntu
    permissions: '0600'
    content: |
${replace(var.public_key, "\n", "\n      ")}

  # -------------------------
  # 3️⃣ DCV auto-session service
  # -------------------------
  - path: /etc/systemd/system/dcv-session.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Create Amazon DCV desktop session
      After=dcvserver.service
      Requires=dcvserver.service

      [Service]
      Type=oneshot
      ExecStart=/usr/bin/dcv create-session desktop --owner ubuntu || true
      RemainAfterExit=yes

      [Install]
      WantedBy=multi-user.target

# -------------------------
# 4️⃣ First boot commands
# -------------------------
runcmd:
  - mkdir -p /home/ubuntu/.ssh
  - chown -R ubuntu:ubuntu /home/ubuntu/.ssh
  - chmod 700 /home/ubuntu/.ssh

  - systemctl enable ssh --now

  - systemctl daemon-reload
  - systemctl enable --now dcv-session.service

  # Safety net (DCV is sometimes slow)
  - /usr/bin/dcv create-session desktop --owner ubuntu || true

  # Give time before Ansible
  - sleep 180
EOT


  lifecycle { ignore_changes = [user_data] }
}
