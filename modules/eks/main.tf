####################################################
# modules/eks/main.tf
# (resources + outputs only — variables are in variables.tf)
####################################################

# Generate unique suffix
resource "random_id" "unique_suffix" {
  byte_length = 4
  keepers = { cluster_name = var.cluster_name }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  count = var.cluster_name != "" ? 1 : 0
  name  = "${var.cluster_name}-eks-cluster-role-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  lifecycle {
    ignore_changes = [id]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.cluster_name != "" ? 1 : 0
  role       = aws_iam_role.eks_cluster_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

  lifecycle {
    ignore_changes = [id]
  }
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  count      = var.cluster_name != "" ? 1 : 0
  role       = aws_iam_role.eks_cluster_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"

  lifecycle {
    ignore_changes = [id]
  }
}

# Security Group
resource "aws_security_group" "eks_cluster" {
  count       = var.cluster_name != "" ? 1 : 0
  name_prefix = "${var.cluster_name}-sg-"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    ignore_changes = [id]
  }
}

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  count    = var.cluster_name != "" && length(var.subnet_ids) > 0 ? 1 : 0
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role[0].arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.eks_cluster[0].id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy
  ]
}

# Fargate Pod Execution Role
resource "aws_iam_role" "fargate_pod_execution_role" {
  count = var.cluster_name != "" && var.use_fargate ? 1 : 0
  name  = "${var.cluster_name}-fargate-pod-execution-role-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
    } ]
  })

  lifecycle {
    ignore_changes = [id]
  }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_policy" {
  count      = var.cluster_name != "" && var.use_fargate ? 1 : 0
  role       = aws_iam_role.fargate_pod_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"

  lifecycle {
    ignore_changes = [id]
  }
}

# Add ECR read permissions for pods running on Fargate so pods can pull images from private ECR.
resource "aws_iam_role_policy_attachment" "fargate_ecr_read" {
  count      = var.cluster_name != "" && var.use_fargate ? 1 : 0
  role       = aws_iam_role.fargate_pod_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

  lifecycle {
    ignore_changes = [id]
  }
}

# Fargate Profiles
resource "aws_eks_fargate_profile" "fargate_profile" {
  count                 = var.use_fargate && length(var.fargate_selectors) > 0 ? length(var.fargate_selectors) : 0
  cluster_name          = aws_eks_cluster.cluster[0].name
  fargate_profile_name  = "${var.cluster_name}-fargate-${count.index}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role[0].arn
  subnet_ids            = var.subnet_ids

  selector {
    namespace = var.fargate_selectors[count.index].namespace
    labels    = lookup(var.fargate_selectors[count.index], "labels", {})
  }

  depends_on = [aws_eks_cluster.cluster]
}

# Create ECR repos for each tool (private repos)
resource "aws_ecr_repository" "tool_repo" {
  for_each = toset(var.tools_to_install)
  name     = "${var.cluster_name}-${each.value}"

  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {}   # empty map = no tags ever set by Terraform

  lifecycle {
    ignore_changes = [
      tags,
      tags_all
    ]
  }
}

# Outputs
output "cluster_name" {
  value = aws_eks_cluster.cluster[0].name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.cluster[0].endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.cluster[0].certificate_authority[0].data
}

output "cluster_id" {
  value = aws_eks_cluster.cluster[0].id
}

output "fargate_profile_names" {
  value = aws_eks_fargate_profile.fargate_profile[*].fargate_profile_name
}

# Map: tool_name -> ecr repository URL
output "ecr_repo_urls" {
  value = { for k, r in aws_ecr_repository.tool_repo : k => r.repository_url }
}

output "kubeconfig" {
  value = <<-EOT
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.cluster[0].endpoint}
    certificate-authority-data: ${aws_eks_cluster.cluster[0].certificate_authority[0].data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - "eks"
        - "get-token"
        - "--cluster-name"
        - "${aws_eks_cluster.cluster[0].name}"
EOT
  sensitive = true
}

