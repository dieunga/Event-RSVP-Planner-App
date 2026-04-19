variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "AWS EC2 Key Pair name"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Name tag for EC2 instance"
  type        = string
  default     = "My Web Server"
}

variable "domain_name" {
  description = "Domain name for Route53 (e.g., example.com)"
  type        = string
  default     = "dieunga.io.vn"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "soiree-eks-cluster"
}

variable "eks_node_instance_type" {
  description = "Instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "soiree"
}

variable "db_username" {
  description = "RDS database master username"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "RDS database master password"
  type        = string
  sensitive   = true
}

variable "ingress_lb_dns" {
  description = "DNS name of the Istio Ingress NLB. Leave empty to auto-discover via tags."
  type        = string
  default     = ""
}