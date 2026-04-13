# ==========================================
# NAT Gateway (for private subnets)
# ==========================================
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags   = { Name = "nat-eip-az-a" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags          = { Name = "nat-gateway-az-a" }
  depends_on    = [aws_internet_gateway.igw]
}

# ==========================================
# Route Tables
# ==========================================
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Public RT" }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "Private RT" }
}

# Public RT associations
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "web_assoc" {
  subnet_id      = aws_subnet.web_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Private RT associations (DB subnets)
resource "aws_route_table_association" "db_a_assoc" {
  subnet_id      = aws_subnet.db_subnet_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_b_assoc" {
  subnet_id      = aws_subnet.db_subnet_b.id
  route_table_id = aws_route_table.private_rt.id
}