output "public_ips" {
  value = { for k, v in aws_instance.this : k => v.public_ip }
}

output "ec2_instance_ids" {
  value = { for k, v in aws_instance.this : k => v.id }
}
