# Generate unique suffix
resource "random_id" "unique_suffix" {
  byte_length = 4
  keepers = { cluster_name = var.cluster_name }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  count = var.cluster_name != null ? 1 : 0
  name  = "${var.cluster_name}-eks-cluster-role-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.cluster_name != null ? 1 : 0
  role       = aws_iam_role.eks_cluster_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  count      = var.cluster_name != null ? 1 : 0
  role       = aws_iam_role.eks_cluster_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

# Security Group
resource "aws_security_group" "eks_cluster" {
  count       = var.cluster_name != null ? 1 : 0
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
}

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  count    = var.cluster_name != null && length(var.subnet_ids) > 0 ? 1 : 0
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
  count = var.cluster_name != null && var.use_fargate ? 1 : 0
  name  = "${var.cluster_name}-fargate-pod-execution-role-${random_id.unique_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_policy" {
  count      = var.cluster_name != null && var.use_fargate ? 1 : 0
  role       = aws_iam_role.fargate_pod_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# Fargate Profiles
resource "aws_eks_fargate_profile" "fargate_profile" {
  count              = var.cluster_name != null && var.use_fargate ? length(var.fargate_selectors) : 0
  cluster_name       = aws_eks_cluster.cluster[0].name
  fargate_profile_name = "${var.cluster_name}-fargate-${count.index}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role[0].arn
  subnet_ids         = var.subnet_ids

  selector {
    namespace = var.fargate_selectors[count.index].namespace
    labels    = lookup(var.fargate_selectors[count.index], "labels", {})
  }

  depends_on = [aws_eks_cluster.cluster]
}

# ECR Repositories for tools
resource "aws_ecr_repository" "tool_repo" {
  for_each = toset(var.tools_to_install)
  name     = "${var.cluster_name}-${each.value}"
}

# Push images to ECR
resource "null_resource" "push_tool_images" {
  for_each = toset(var.tools_to_install)

  triggers = {
    repo_url = aws_ecr_repository.tool_repo[each.value].repository_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.tool_repo[each.value].repository_url}
      docker pull bitnami/${each.value}:latest
      docker tag bitnami/${each.value}:latest ${aws_ecr_repository.tool_repo[each.value].repository_url}:latest
      docker push ${aws_ecr_repository.tool_repo[each.value].repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.tool_repo]
}

# Helm Provider
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.cluster[0].endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.cluster[0].certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.cluster[0].name]
    }
  }
}

# Helm Releases for tools
resource "helm_release" "tool" {
  for_each  = toset(var.tools_to_install)
  name      = each.value
  namespace = "default"
  repository = "https://charts.bitnami.com/bitnami"
  chart     = each.value
  version   = "latest"
  create_namespace = true

  set {
    name  = "image.repository"
    value = aws_ecr_repository.tool_repo[each.value].repository_url
  }

  set {
    name  = "image.tag"
    value = "latest"
  }

  depends_on = [
    null_resource.push_tool_images,
    aws_eks_fargate_profile.fargate_profile
  ]
}

data "aws_region" "current" {}

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
