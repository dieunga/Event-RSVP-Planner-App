# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name   = "soiree-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432 # Using PostgreSQL as an example
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "soiree-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

# RDS Instance (Cost Optimized)
resource "aws_db_instance" "app_db" {
  identifier           = "soiree-db"
  allocated_storage    = 20
  storage_type         = "gp3"
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = "db.t4g.micro" # AWS Graviton2 - highly cost effective
  db_name              = "soireedb"
  username             = "dbadmin"
  password             = "ChangeThisSecurePassword123!" # Use AWS Secrets Manager in prod
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true # Set to false for production
  publicly_accessible  = false
}

# SNS Topic for Event RSVPs
resource "aws_sns_topic" "rsvp_notifications" {
  name = "soiree-rsvp-confirmations"
}