output "instance_ids" {
  description = "The instance IDs"
  value       = aws_instance.ghes.*.id
}

output "private_ips" {
  description = "The instance private IPs"
  value       = aws_instance.ghes.*.private_ip
}

output "public_ips" {
  description = "The instance public IPs"
  value       = aws_instance.ghes.*.public_ip
}

output "elastic_ips" {
  description = "The instance elastic IPs"
  value       = aws_eip.ghes_eip.*.public_ip
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = aws_instance.ghes.*.subnet_id
}

output "security_group" {
  description = "GHES Security Group ID"
  value       = aws_instance.ghes.0.vpc_security_group_ids
}
