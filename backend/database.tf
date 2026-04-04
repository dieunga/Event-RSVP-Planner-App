resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.db_subnet.id, aws_subnet.db_subnet_dummy.id]
  
  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "primary_db" {
  identifier             = "primary-database"
  allocated_storage      = 20
  storage_type           = "gp3"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = "admin123"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  
  multi_az               = false
  skip_final_snapshot    = false
}