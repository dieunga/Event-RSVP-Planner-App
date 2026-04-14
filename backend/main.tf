# ==========================================
# VPC & Internet Gateway
# ==========================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "my-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "main-igw" }
}

# ==========================================
# Subnets
# ==========================================
# Public subnet (for NAT Gateway + NLB AZ A) - AZ A
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "Public Subnet - AZ A"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Public subnet (for NLB AZ B) - AZ B
resource "aws_subnet" "eks_public_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.7.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "EKS Public Subnet - AZ B"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Web subnet (for EC2) - AZ A
resource "aws_subnet" "web_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Web Subnet - AZ A"
  }
}

# EKS private subnets (for worker nodes)
resource "aws_subnet" "eks_private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name                                        = "EKS Private Subnet - AZ A"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_subnet" "eks_private_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name                                        = "EKS Private Subnet - AZ B"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# DB subnets (for RDS - requires 2 AZs)
resource "aws_subnet" "db_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "DB Subnet - AZ A" }
}

resource "aws_subnet" "db_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"
  tags = { Name = "DB Subnet - AZ B" }
}

# ==========================================
# Route 53
# ==========================================
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# Route53 A record for main domain is managed in cloudfront.tf (CloudFront alias)

# ==========================================
# EC2 Instance
# ==========================================
resource "aws_eip" "ec2_eip" {
  domain = "vpc"
  tags   = { Name = "ec2-web-eip" }
}

resource "aws_eip_association" "ec2_eip_assoc" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.ec2_eip.id
}

resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.web_subnet.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    s3_bucket      = aws_s3_bucket.static_storage.bucket
    aws_region     = var.aws_region
    rds_address    = aws_db_instance.primary_db.address
    db_name        = "webdb"
    db_username    = var.db_username
    db_password    = var.db_password
    notify_api_url = "${aws_apigatewayv2_stage.default.invoke_url}/notify"
  })

  depends_on = [
    aws_db_instance.primary_db,
    aws_s3_object.frontend_files,
    aws_apigatewayv2_stage.default,
  ]

  tags = { Name = var.instance_name }
}

# ==========================================
# S3 & SNS (Storage & Notifications)
# ==========================================
resource "aws_s3_bucket" "static_storage" {
  bucket_prefix = "website-bucket"
}

resource "aws_sns_topic" "alerts" {
  name = "system-alerts"
}

# ==========================================
# IAM Role for EC2 (S3 read access)
# ==========================================
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.ec2_role.name
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ==========================================
# Frontend files uploaded to S3
# ==========================================
locals {
  frontend_files = toset([
    "index.php", "index.html", "login.php", "login.html",
    "logout.php", "signup.php", "signup.html", "styles.css", "app.js"
  ])
  content_types = {
    "php"  = "application/x-httpd-php"
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
  }
}

resource "aws_s3_object" "frontend_files" {
  for_each = local.frontend_files

  bucket       = aws_s3_bucket.static_storage.id
  key          = "app/${each.key}"
  source       = "${path.module}/../frontend/${each.key}"
  etag         = filemd5("${path.module}/../frontend/${each.key}")
  content_type = lookup(local.content_types, element(split(".", each.key), length(split(".", each.key)) - 1), "application/octet-stream")
}