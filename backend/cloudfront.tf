# ==========================================
# ACM Certificate (must be in us-east-1 for CloudFront)
# ==========================================
# provider "aws" {
#   alias  = "us_east_1"
#   region = "us-east-1"
# }

# resource "aws_acm_certificate" "cloudfront_cert" {
#   provider          = aws.us_east_1
#   domain_name       = var.domain_name
#   validation_method = "DNS"

#   lifecycle {
#     create_before_destroy = true
#   }

#   tags = { Name = "${var.project_name}-cloudfront-cert" }
# }

# resource "aws_route53_record" "cert_validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.cloudfront_cert.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }

#   zone_id = aws_route53_zone.main.zone_id
#   name    = each.value.name
#   type    = each.value.type
#   records = [each.value.record]
#   ttl     = 60

#   allow_overwrite = true
# }

# resource "aws_acm_certificate_validation" "cloudfront_cert" {
#   provider                = aws.us_east_1
#   certificate_arn         = aws_acm_certificate.cloudfront_cert.arn
#   validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
# }

# # ==========================================
# # CloudFront Distribution
# # ==========================================
# resource "aws_cloudfront_distribution" "main" {
#   enabled             = true
#   is_ipv6_enabled     = true
#   comment             = "${var.project_name} CloudFront Distribution"
#   aliases             = [var.domain_name]
#   price_class         = "PriceClass_200"
#   wait_for_deployment = false

#   # Origin: Istio Ingress Gateway NLB
#   origin {
#     domain_name = data.aws_lb.ingress_lb.dns_name
#     origin_id   = "istio-ingress"

#     custom_origin_config {
#       http_port              = 80
#       https_port             = 443
#       origin_protocol_policy = "http-only"
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }

#   # Default behavior (frontend static assets)
#   default_cache_behavior {
#     target_origin_id       = "istio-ingress"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD", "OPTIONS"]
#     cached_methods         = ["GET", "HEAD"]
#     compress               = true

#     forwarded_values {
#       query_string = false
#       cookies {
#         forward = "none"
#       }
#     }

#     min_ttl     = 0
#     default_ttl = 3600
#     max_ttl     = 86400
#   }

#   # API paths — no caching, forward everything
#   ordered_cache_behavior {
#     path_pattern           = "/api/*"
#     target_origin_id       = "istio-ingress"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
#     cached_methods         = ["GET", "HEAD"]
#     compress               = true

#     forwarded_values {
#       query_string = true
#       headers      = ["Authorization", "Origin", "Accept"]
#       cookies {
#         forward = "all"
#       }
#     }

#     min_ttl     = 0
#     default_ttl = 0
#     max_ttl     = 0
#   }

#   # TLS certificate
#   viewer_certificate {
#     acm_certificate_arn      = aws_acm_certificate_validation.cloudfront_cert.certificate_arn
#     ssl_support_method       = "sni-only"
#     minimum_protocol_version = "TLSv1.2_2021"
#   }

#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }

#   tags = { Name = "${var.project_name}-cloudfront" }

#   depends_on = [aws_eks_node_group.main]
# }
