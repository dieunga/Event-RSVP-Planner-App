# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Subnets 
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true

  tags = { Name = "Public Subnet" }
}

resource "aws_subnet" "web_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-southeast-1a"

  tags = { Name = "Web Subnet" }
}

resource "aws_subnet" "db_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-southeast-1a"

  tags = { Name = "DB Primary Subnet" }
}

# Dummy DB Subnet
resource "aws_subnet" "db_subnet_dummy" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-southeast-1b" 

  tags = { Name = "DB Subnet (Dummy - AZ B)" }
}

# EC2 Instance
resource "aws_instance" "web_vm" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.key.key_name
  associate_public_ip_address = true

  tags = {
    Name = var.instance_name
  }
}