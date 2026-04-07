# ==========================================
# Security Groups
# ==========================================
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP/HTTPS from Internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP and SSH direct access for testing"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Direct HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow DB inbound traffic from Web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# WAF (Web Application Firewall)
# ==========================================
resource "aws_wafv2_web_acl" "web_acl" {
  name        = "web-acl"
  description = "Basic WAF for ALB"
  scope       = "REGIONAL" 

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "waf_alb_assoc" {
  resource_arn = aws_lb.web_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}