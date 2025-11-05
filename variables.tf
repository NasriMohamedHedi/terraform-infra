variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "eu-central-1"
}

variable "s3_payload_bucket" {
  description = "S3 bucket containing the payload"
  type        = string
}

variable "s3_payload_key" {
  description = "S3 key for the payload file"
  type        = string
}

variable "jenkins_url" {
  description = "URL of the Jenkins server"
  type        = string
  default     = "https://9216d38c2a3f.ngrok-free.app"
}

# NEW: toggle ECR repo creation (set to false while debugging/prototyping Jenkins user permissions)
variable "create_ecr_repos" {
  description = "When false, module.eks will not create/read ECR repositories (useful if Jenkins IAM lacks ECR permissions)"
  type        = bool
  default     = true
}

