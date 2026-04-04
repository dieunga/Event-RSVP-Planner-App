# Retrieve latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_launch_template" "web_template" {
  name_prefix   = "web-template-"
  image_id      = data.aws_ami.ubuntu_22_04.id
  instance_type = var.instance_type

  network_interfaces {
    security_groups = [aws_security_group.web_sg.id]
    subnet_id       = aws_subnet.web_subnet.id
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update -y
              apt install -y apache2
              systemctl start apache2
              systemctl enable apache2
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