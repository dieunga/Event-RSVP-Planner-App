# ==========================================
# VPC & Internet Gateway
# ==========================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "my-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "main-igw" }
}

# ==========================================
# Subnets
# ==========================================
# AZ A (Left Side) 
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "Public Subnet - AZ A" }
}

resource "aws_subnet" "db_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "DB Subnet - AZ A" }
}

# AZ B (Right Side) 
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.5.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "Public Subnet - AZ B" }
}

resource "aws_subnet" "web_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "Web Subnet - AZ B" }
}

resource "aws_subnet" "db_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "DB Subnet - AZ B" }
}

# ==========================================
# Route 53 & ACM (Certificate Manager)
# ==========================================
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# resource "aws_acm_certificate" "cert" {
#   domain_name       = var.domain_name
#   validation_method = "DNS"
#   tags = { Name = "Web Cert" }
# }

# ==========================================
# CloudFront (CDN)
# ==========================================
# resource "aws_cloudfront_distribution" "web_cdn" {
#   enabled = true

#   origin {
#     domain_name = aws_lb.web_alb.dns_name
#     origin_id   = "ALBOrigin"
#     custom_origin_config {
#       http_port              = 80
#       https_port             = 443
#       origin_protocol_policy = "http-only"
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }

#   default_cache_behavior {
#     target_origin_id       = "ALBOrigin"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD", "OPTIONS"]
#     cached_methods         = ["GET", "HEAD"]
#     forwarded_values {
#       query_string = false
#       cookies { forward = "none" }
#     }
#   }

#   restrictions {
#     geo_restriction { restriction_type = "none" }
#   }

#   viewer_certificate {
#     cloudfront_default_certificate = true 
#   }
# }

# ==========================================
# S3 & SNS (Storage & Notifications)
# ==========================================
resource "aws_s3_bucket" "static_storage" {
  bucket_prefix = "website-bucket"
}

resource "aws_sns_topic" "alerts" {
  name = "system-alerts"
}