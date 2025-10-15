provider "aws" {
  region = var.aws_region
}

# EC2-specific resources
resource "random_id" "unique_suffix" {
  byte_length = 4
  count       = local.payload.service_type == "ec2" ? 1 : 0
}

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
  count     = local.payload.service_type == "ec2" ? 1 : 0
}

resource "aws_key_pair" "ec2_key_pair" {
  count      = local.payload.service_type == "ec2" ? 1 : 0
  key_name   = "client-access-key-${random_id.unique_suffix[0].hex}"
  public_key = tls_private_key.ec2_key[0].public_key_openssh
  lifecycle {
    ignore_changes = [key_name]
  }
}

# EC2 output
output "private_key_pem" {
  value     = local.payload.service_type == "ec2" ? tls_private_key.ec2_key[0].private_key_pem : null
  sensitive = true
}

# Data source to read JSON payload from S3
data "aws_s3_object" "payload" {
  bucket = var.s3_payload_bucket
  key    = var.s3_payload_key
}

# Local variables for payload processing
locals {
  payload = jsondecode(data.aws_s3_object.payload.body)

  # EC2-specific locals
  instance_keys    = local.payload.service_type == "ec2" ? keys(local.payload.instances) : []
  instance_config  = local.payload.service_type == "ec2" ? local.payload.instances[local.instance_keys[0]] : null
  subnet_id        = local.instance_config != null ? lookup(local.instance_config, "subnet_id", "subnet-DEFAULT") : null

  # EKS-specific locals
  eks_config         = local.payload.service_type == "eks" ? local.payload.eks : null
  cluster_name       = local.eks_config != null ? local.eks_config.cluster_name : null
  kubernetes_version = local.eks_config != null ? local.eks_config.kubernetes_version : "1.29"
  vpc_id             = local.eks_config != null ? local.eks_config.vpc_id : null
  subnet_ids         = local.eks_config != null ? local.eks_config.subnet_ids : []
  use_fargate        = local.eks_config != null ? local.eks_config.use_fargate : false
  fargate_selectors  = local.eks_config != null ? local.eks_config.fargate_selectors : []
  owner_name         = local.eks_config != null ? local.eks_config.Owner : null

  # Validation to ensure required fields are present
  validate_eks = local.eks_config != null ? (
    local.cluster_name != "" &&
    local.vpc_id != "" &&
    length(local.subnet_ids) > 0 &&
    local.owner_name != ""
  ) : true
}

# Module deployment for EC2
module "ec2" {
  source           = "./modules/ec2"
  count            = local.payload.service_type == "ec2" ? 1 : 0
  instances        = local.payload.instances
  key_name         = aws_key_pair.ec2_key_pair[0].key_name
  public_key       = tls_private_key.ec2_key[0].public_key_openssh
  security_group_id = local.instance_config != null ? local.instance_config.security_groups[0] : null
  subnet_id        = local.subnet_id
}

# Module deployment for EKS
module "eks" {
  source             = "./modules/eks"
  count              = local.payload.service_type == "eks" && local.validate_eks ? 1 : 0
  cluster_name       = local.cluster_name
  kubernetes_version = local.kubernetes_version
  subnet_ids         = local.subnet_ids
  vpc_id             = local.vpc_id
  use_fargate        = local.use_fargate
  fargate_selectors  = local.fargate_selectors
  owner_name         = local.owner_name
}

# Outputs for EC2 public IPs
output "ec2_public_ips" {
  value = local.payload.service_type == "ec2" ? module.ec2[0].public_ips : null
}

# Outputs for EKS cluster details
output "cluster_name" {
  value = local.payload.service_type == "eks" && local.validate_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  value = local.payload.service_type == "eks" && local.validate_eks ? module.eks[0].cluster_endpoint : null
}

output "eks_cluster_certificate_authority_data" {
  value = local.payload.service_type == "eks" && local.validate_eks ? module.eks[0].cluster_certificate_authority_data : null
}
