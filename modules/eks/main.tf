data "aws_eks_cluster_auth" "cluster" {
  name = try(aws_eks_cluster.cluster[0].name, "")
}

resource "random_id" "unique_suffix" {
  byte_length = 4
  keepers = {
    cluster_name = var.cluster_name
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  count = var.cluster_name != "" ? 1 : 0
  name  = "${var.cluster_name}-eks-cluster-role-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
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

resource "aws_security_group" "eks_cluster" {
  count       = var.cluster_name != "" ? 1 : 0
  name_prefix = "${var.cluster_name}-sg-"
  description = "EKS cluster security group"
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

# IAM for Node Group (EC2)
resource "aws_iam_role" "node_group_role" {
  count = var.create_node_group && var.cluster_name != "" ? 1 : 0

  name = "${var.cluster_name}-nodegroup-role-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  lifecycle {
    ignore_changes = [id]
  }
}

resource "aws_iam_role_policy_attachment" "worker_node" {
  count      = length(aws_iam_role.node_group_role) > 0 ? 1 : 0
  role       = aws_iam_role.node_group_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni" {
  count      = length(aws_iam_role.node_group_role) > 0 ? 1 : 0
  role       = aws_iam_role.node_group_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  count      = length(aws_iam_role.node_group_role) > 0 ? 1 : 0
  role       = aws_iam_role.node_group_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "node_group" {
  count = var.create_node_group && var.cluster_name != "" ? 1 : 0

  cluster_name    = aws_eks_cluster.cluster[0].name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node_group_role[0].arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = var.node_group_desired_size
    min_size     = var.node_group_min_size
    max_size     = var.node_group_max_size
  }

  instance_types = var.node_group_instance_types
  disk_size      = var.node_group_disk_size

  tags = merge({
    "Name" = "${var.cluster_name}-ng"
  }, var.node_group_tags)

  depends_on = [
    aws_eks_cluster.cluster
  ]
}

# ECR repos logic (unchanged)
resource "aws_ecr_repository" "tool_repo" {
  for_each = toset(var.create_ecr_repos ? var.tools_to_install : [])

  name                  = "${var.cluster_name}-${each.value}"
  image_tag_mutability  = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Outputs
output "cluster_name" {
  value = try(aws_eks_cluster.cluster[0].name, null)
}

output "cluster_endpoint" {
  value = try(aws_eks_cluster.cluster[0].endpoint, null)
}

output "cluster_certificate_authority_data" {
  value = try(aws_eks_cluster.cluster[0].certificate_authority[0].data, null)
}

output "cluster_id" {
  value = try(aws_eks_cluster.cluster[0].id, null)
}

output "node_group_names" {
  value = try([for ng in aws_eks_node_group.node_group : ng.node_group_name], [])
}

