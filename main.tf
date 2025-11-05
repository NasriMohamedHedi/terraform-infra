terraform {
  required_version = ">= 1.4.0, < 2.0.0"

  required_providers {
    # Pin to 5.x so we avoid provider 6.x breaking changes with legacy state
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70, < 6.0"
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

  # keep these "skip" flags if you need terraform to run in CI without metadata checks
  skip_requesting_account_id  = false
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true

  ignore_tags {
    keys         = []
    key_prefixes = []
  }

  default_tags {
    tags = {}
  }
}

# Defensive helm provider in root (safe when cluster not yet created).
# It references module outputs using try() to avoid hard failures during init.
provider "helm" {
  kubernetes {
    host                   = try(module.eks[0].cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks[0].cluster_certificate_authority_data), "")
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", try(module.eks[0].cluster_name, "")]
    }
  }
}

data "aws_s3_object" "payload" {
  bucket = var.s3_payload_bucket
  key    = var.s3_payload_key
}

locals {
  payload = jsondecode(data.aws_s3_object.payload.body)

  # defensive default: ensure payload.eks exists and is an object/map
  payload_eks = try(local.payload.eks, {})

  # EC2 (unchanged behavior)
  is_ec2           = local.payload.service_type == "ec2"
  instance_keys    = local.is_ec2 ? keys(local.payload.instances) : []
  first_instance   = local.is_ec2 && length(local.instance_keys) > 0 ? local.payload.instances[local.instance_keys[0]] : null
  subnet_id        = local.first_instance != null ? lookup(local.first_instance, "subnet_id", null) : null
  security_groups  = local.first_instance != null ? lookup(local.first_instance, "security_groups", []) : []

  # EKS flags & defensive parsing
  is_eks = local.payload.service_type == "eks"

  # normalize subnet_ids -> list(string)
  eks_subnet_ids_raw = lookup(local.payload_eks, "subnet_ids", [])
  eks_subnet_ids = [for id in local.eks_subnet_ids_raw : tostring(id)]

  # normalize fargate selectors to object list { namespace, labels = map(string) }
  eks_fargate_raw = lookup(local.payload_eks, "fargate_selectors", [])
  eks_fargate_selectors = [
    for s in local.eks_fargate_raw : {
      namespace = tostring(lookup(s, "namespace", "default"))
      labels    = { for k, v in try(lookup(s, "labels", {}), {}) : k => tostring(v) }
    }
  ]

  # normalize tools_to_install -> list(string)
  eks_tools_raw = lookup(local.payload_eks, "tools_to_install", [])
  eks_tools = [
    for t in local.eks_tools_raw :
    can(tostring(t)) ? tostring(t) :
    (can(t["name"]) ? tostring(t["name"]) :
    (can(t["tool"]) ? tostring(t["tool"]) : jsonencode(t)))
  ]

  eks_config = {
    cluster_name       = tostring(lookup(local.payload_eks, "cluster_name", ""))
    vpc_id             = tostring(lookup(local.payload_eks, "vpc_id", ""))
    subnet_ids         = local.eks_subnet_ids
    use_fargate        = lookup(local.payload_eks, "use_fargate", false)
    fargate_selectors  = local.eks_fargate_selectors
    Owner              = tostring(lookup(local.payload_eks, "Owner", ""))
    tools_to_install   = local.eks_tools
    kubernetes_version = tostring(lookup(local.payload_eks, "kubernetes_version", "1.29"))
  }

  validate_eks = local.is_eks ? (
    local.eks_config.cluster_name != "" &&
    local.eks_config.vpc_id != "" &&
    length(local.eks_config.subnet_ids) > 0 &&
    local.eks_config.Owner != ""
  ) : true
}

# ----------------
# EC2 Key Pair (unchanged)
# ----------------
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

# EC2 Module (unchanged)
module "ec2" {
  source          = "./modules/ec2"
  count           = local.is_ec2 ? 1 : 0
  instances       = local.payload.instances
  key_name        = local.is_ec2 ? aws_key_pair.ec2_key_pair[0].key_name : null
  public_key      = local.is_ec2 ? tls_private_key.ec2_key[0].public_key_openssh : null
  security_groups = local.security_groups
  subnet_id       = local.subnet_id
}

# EKS Module (normalized inputs)
module "eks" {
  source = "./modules/eks"

  count = local.is_eks && local.validate_eks ? 1 : 0

  cluster_name       = local.eks_config.cluster_name
  kubernetes_version = local.eks_config.kubernetes_version
  vpc_id             = local.eks_config.vpc_id
  subnet_ids         = local.eks_config.subnet_ids
  use_fargate        = local.eks_config.use_fargate
  fargate_selectors  = local.eks_config.use_fargate ? local.eks_config.fargate_selectors : []
  owner_name         = local.eks_config.Owner
  tools_to_install   = local.eks_config.tools_to_install
  aws_region         = var.aws_region

  # new optional toggle — set to false to avoid creating/reading ECR repos
  create_ecr_repos   = var.create_ecr_repos
}

# Outputs
output "ec2_public_ips" {
  value = local.is_ec2 ? module.ec2[0].public_ips : null
}

output "ec2_instance_ids" {
  value = local.is_ec2 ? module.ec2[0].ec2_instance_ids : null
}

output "eks_cluster_name" {
  value = try(module.eks[0].cluster_name, null)
}

output "eks_kubeconfig" {
  value     = try(module.eks[0].kubeconfig, null)
  sensitive = true
}

output "eks_ecr_repo_urls" {
  value = try(module.eks[0].ecr_repo_urls, null)
}

