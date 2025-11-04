variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  nullable    = false
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "fargate_selectors" {
  description = "List of Fargate selectors"
  type        = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  default     = []
}

variable "owner_name" {
  description = "Owner of the cluster"
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
  nullable    = true
}

variable "use_fargate" {
  description = "Enable Fargate"
  type        = bool
  default     = false
}

variable "tools_to_install" {
  description = "List of tools to deploy via Helm/ECR"
  type        = list(string)
  default     = []
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

