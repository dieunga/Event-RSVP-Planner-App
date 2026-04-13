# ==========================================
# Outputs
# ==========================================
output "ec2_public_ip" {
  description = "EC2 web server public IP (EIP)"
  value       = aws_eip.ec2_eip.public_ip
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.primary_db.endpoint
}

output "route53_zone_id" {
  description = "Route53 zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_nameservers" {
  description = "Route53 nameservers for domain delegation"
  value       = aws_route53_zone.main.name_servers
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}