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
    ## --- set ubuntu password (plain text) ---
    chpasswd:
      list: |
        ubuntu:ubuntu
      expire: False

    ## --- write the authorized_key from Terraform var.public_key ---
    write_files:
      - path: /home/ubuntu/.ssh/authorized_keys
        owner: ubuntu:ubuntu
        permissions: '0600'
        content: |
${replace(var.public_key, "\n", "\n          ")}

      # ensure DCV uses PAM auth (create or append minimal config)
      - path: /etc/dcv/dcv.conf
        owner: root:root
        permissions: '0644'
        content: |
          [authentication]
          pam-authentication=true

      # systemd service to create a DCV session once dcvserver is up
      - path: /etc/systemd/system/dcv-session.service
        owner: root:root
        permissions: '0644'
        content: |
          [Unit]
          Description=Create DCV session for ubuntu
          After=dcvserver.service
          Wants=dcvserver.service

          [Service]
          Type=oneshot
          ExecStart=/usr/bin/dcv create-session desktop --owner ubuntu || true
          RemainAfterExit=yes

          [Install]
          WantedBy=multi-user.target

    ## --- run once on first boot ---
    runcmd:
      # ensure ssh is enabled and owner/perm for key is correct
      - [ bash, -lc, "mkdir -p /home/ubuntu/.ssh && chown -R ubuntu:ubuntu /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh || true" ]
      - [ bash, -lc, "chmod 600 /home/ubuntu/.ssh/authorized_keys || true" ]
      # ensure DCV config (if DCV package creates its own dcv.conf later, this file still ensures pam is enabled)
      - [ bash, -lc, "if grep -q '^pam-authentication' /etc/dcv/dcv.conf 2>/dev/null; then sed -i 's/^pam-authentication=.*/pam-authentication=true/' /etc/dcv/dcv.conf || true; else echo -e '\n[authentication]\npam-authentication=true' >> /etc/dcv/dcv.conf; fi" ]
      - [ bash, -lc, "systemctl daemon-reload || true" ]
      - [ bash, -lc, "systemctl enable --now dcv-session.service || true" ]
      - [ bash, -lc, "systemctl restart dcvserver || true" ]
      - [ bash, -lc, "systemctl enable --now ssh || true" ]

    final_message: "cloud-init finished"
  EOT


  lifecycle { ignore_changes = [user_data] }
}
