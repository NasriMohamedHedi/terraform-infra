variable "instances" {
  type = map(object({
    ami              = string
    instance_type    = string
    name             = string
    security_groups  = list(string)
    subnet_id        = string
    key_name         = optional(string)
    tags             = optional(map(string))
    tools_to_install = optional(list(string))
  }))
}

variable "security_groups" {
  type    = list(string)
  default = []
}

variable "subnet_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "public_key" {
  type = string
}
