variable "instances" {
  description = "Map of EC2 instance configurations"
  type = map(object({
    ami                    = string
    instance_type          = string
    user_data              = optional(string)
    name                   = string
    security_groups        = list(string)
    key_name               = optional(string, "client-access-key")
    tags                   = optional(map(string))
    compliance_requirements = optional(list(string))
    tools_to_install       = optional(list(string))
  }))
}

variable "security_group_id" {
  description = "Security group ID for the instances"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the instances"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "public_key" {
  description = "Public key for SSH access"
  type        = string
}
