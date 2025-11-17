variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = []
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "owner_name" {
  description = "Owner of the cluster"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
  default     = ""
}

variable "tools_to_install" {
  description = "List of tools to deploy via Helm/ECR (list of string or names)"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "create_ecr_repos" {
  description = "Whether to create ECR repositories for the listed tools"
  type        = bool
  default     = false
}

# New variables for node group (EC2 workers)
variable "create_node_group" {
  description = "Create a managed EKS node group"
  type        = bool
  default     = true
}

variable "node_group_instance_types" {
  description = "EC2 instance types for node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "node_group_disk_size" {
  description = "Disk size in GB for each node"
  type        = number
  default     = 20
}

variable "node_group_tags" {
  description = "Tags to apply to node group instances"
  type        = map(string)
  default     = {}
}

