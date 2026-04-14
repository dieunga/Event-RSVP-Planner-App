# ==========================================
# Security Groups
# ==========================================

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.cluster_name}-cluster-sg" }
}

# EC2 Web Server Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-web-sg"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

  tags = { Name = "ec2-web-sg" }
}

# RDS Database Security Group (allows access from EC2 web subnet + EKS worker subnets)
resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow DB inbound traffic from web subnet"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "db-sg" }
}

# Separate security group rules to avoid destroying SG during updates
resource "aws_security_group_rule" "db_web_subnet" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["10.0.2.0/24"]
  security_group_id = aws_security_group.db_sg.id
  description       = "MySQL from web subnet"
}

resource "aws_security_group_rule" "db_eks_private_a" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["10.0.5.0/24"]
  security_group_id = aws_security_group.db_sg.id
  description       = "MySQL from EKS private subnet AZ A"
}

resource "aws_security_group_rule" "db_eks_private_b" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = ["10.0.6.0/24"]
  security_group_id = aws_security_group.db_sg.id
  description       = "MySQL from EKS private subnet AZ B"
}