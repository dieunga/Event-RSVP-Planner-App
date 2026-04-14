# ==========================================
# Outputs
# ==========================================
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "ecr_auth_service_url" {
  value = aws_ecr_repository.auth_service.repository_url
}

output "ecr_event_service_url" {
  value = aws_ecr_repository.event_service.repository_url
}

output "ecr_rsvp_service_url" {
  value = aws_ecr_repository.rsvp_service.repository_url
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "notify_api_url" {
  description = "API Gateway URL for Lambda notification endpoint"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/notify"
}

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