terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes {
    host                   = try(module.eks["eks"].cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks["eks"].cluster_certificate_authority_data), "")
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", try(module.eks["eks"].cluster_name, "")]
    }
  }
}

data "aws_s3_object" "payload" {
  bucket = var.s3_payload_bucket
  key    = var.s3_payload_key
}

locals {
  payload = jsondecode(data.aws_s3_object.payload.body)

  # EC2
  is_ec2           = local.payload.service_type == "ec2"
  instance_keys    = local.is_ec2 ? keys(local.payload.instances) : []
  first_instance   = local.is_ec2 && length(local.instance_keys) > 0 ? local.payload.instances[local.instance_keys[0]] : null
  subnet_id        = local.first_instance != null ? lookup(local.first_instance, "subnet_id", null) : null
  security_groups  = local.first_instance != null ? lookup(local.first_instance, "security_groups", []) : []

  # EKS
  is_eks = local.payload.service_type == "eks"

  eks_config = local.is_eks ? {
    cluster_name       = lookup(local.payload.eks, "cluster_name", null)
    vpc_id             = lookup(local.payload.eks, "vpc_id", null)
    subnet_ids         = lookup(local.payload.eks, "subnet_ids", [])
    use_fargate        = lookup(local.payload.eks, "use_fargate", false)
    fargate_selectors  = lookup(local.payload.eks, "fargate_selectors", [])
    Owner              = lookup(local.payload.eks, "Owner", null)
    tools_to_install   = lookup(local.payload.eks, "tools_to_install", [])
    kubernetes_version = lookup(local.payload.eks, "kubernetes_version", "1.29")
  } : {
    cluster_name       = null
    vpc_id             = null
    subnet_ids         = []
    use_fargate        = false
    fargate_selectors  = []
    Owner              = null
    tools_to_install   = []
    kubernetes_version = "1.29"
  }

  validate_eks = local.is_eks ? (
    local.eks_config.cluster_name != null &&
    local.eks_config.vpc_id != null &&
    length(local.eks_config.subnet_ids) > 0 &&
    local.eks_config.Owner != null
  ) : true
}

# EC2 Key Pair
resource "random_id" "unique_suffix" {
  count       = local.is_ec2 ? 1 : 0
  byte_length = 4
}

resource "tls_private_key" "ec2_key" {
  count     = local.is_ec2 ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key_pair" {
  count      = local.is_ec2 ? 1 : 0
  key_name   = "client-access-key-${random_id.unique_suffix[0].hex}"
  public_key = tls_private_key.ec2_key[0].public_key_openssh
}

output "private_key_pem" {
  value     = local.is_ec2 ? tls_private_key.ec2_key[0].private_key_pem : null
  sensitive = true
}

# EC2 Module
module "ec2" {
  source          = "./modules/ec2"
  count           = local.is_ec2 ? 1 : 0
  instances       = local.payload.instances
  key_name        = local.is_ec2 ? aws_key_pair.ec2_key_pair[0].key_name : null
  public_key      = local.is_ec2 ? tls_private_key.ec2_key[0].public_key_openssh : null
  security_groups = local.security_groups
  subnet_id       = local.subnet_id
}

# EKS Module
module "eks" {
  source             = "./modules/eks"
  for_each           = local.is_eks && local.validate_eks ? toset(["eks"]) : toset([])

  cluster_name       = local.eks_config.cluster_name
  kubernetes_version = local.eks_config.kubernetes_version
  vpc_id             = local.eks_config.vpc_id
  subnet_ids         = local.eks_config.subnet_ids
  use_fargate        = local.eks_config.use_fargate
  fargate_selectors  = local.eks_config.fargate_selectors
  owner_name         = local.eks_config.Owner
  tools_to_install   = local.eks_config.tools_to_install
  aws_region         = var.aws_region

  providers = {
    aws  = aws
    helm = helm
  }
}

# Outputs
output "ec2_public_ips" {
  value = local.is_ec2 ? module.ec2[0].public_ips : null
}

output "ec2_instance_ids" {
  value = local.is_ec2 ? module.ec2[0].ec2_instance_ids : null
}

output "eks_cluster_name" {
  value = try(module.eks["eks"].cluster_name, null)
}

output "eks_kubeconfig" {
  value     = try(module.eks["eks"].kubeconfig, null)
  sensitive = true
}
