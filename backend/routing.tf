# ==========================================
# NAT Gateway
# ==========================================
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_b.id
  tags = { Name = "nat-gateway-az-b" }
  depends_on = [aws_internet_gateway.igw]
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
  route {
    cidr_block     = "10.0.0.0/16"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "Public RT" }
}

resource "aws_route_table" "private_rt_b" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  tags = { Name = "Private RT - AZ B" }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "web_b_assoc" {
  subnet_id      = aws_subnet.web_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "db_a_assoc" {
  subnet_id      = aws_subnet.db_subnet_a.id
  route_table_id = aws_route_table.private_rt_b.id
}
resource "aws_route_table_association" "db_b_assoc" {
  subnet_id      = aws_subnet.db_subnet_b.id
  route_table_id = aws_route_table.private_rt_b.id
}

# ==========================================
# Load Balancer (ALB)
# ==========================================
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "web_listener_http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}