# Retrieve latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "web_template" {
  name_prefix   = "web-template-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    subnet_id       = aws_subnet.web_subnet.id
  }

  user_data = filebase64encodes(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello from the Left Side Web Server!" > /var/www/html/index.html
              EOF
  )
}

resource "aws_autoscaling_group" "web_asg" {
  name                = "web-asg"
  vpc_zone_identifier = [aws_subnet.web_subnet.id]
  desired_capacity    = 1
  min_size            = 1
  max_size            = 2

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }
}
