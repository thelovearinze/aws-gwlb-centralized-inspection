resource "aws_vpc" "security_vpc" {
  cidr_block           = "198.18.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "security-hub-vpc" }
}

# 1. The Fresh Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "fresh-key-pair"
  public_key = file("./fresh-key.pub")
}

resource "aws_subnet" "gwlb_subnet" {
  vpc_id            = aws_vpc.security_vpc.id
  cidr_block        = "198.18.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "gwlb-subnet" }
}

# GWLB & Target Group
resource "aws_lb" "security_gwlb" {
  name               = "security-gateway-lb"
  load_balancer_type = "gateway"
  subnets            = [aws_subnet.gwlb_subnet.id]
}

resource "aws_lb_target_group" "gwlb_tg" {
  name     = "gwlb-target-group"
  port     = 6081
  protocol = "GENEVE"
  vpc_id   = aws_vpc.security_vpc.id
  health_check {
    port     = 80
    protocol = "HTTP" 
  }
}

# Firewall Security Group
resource "aws_security_group" "firewall_sg" {
  name   = "firewall-sg"
  vpc_id = aws_vpc.security_vpc.id

  ingress {
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
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

# Inspection Instance
resource "aws_instance" "firewall" {
  ami                         = "ami-0c7217cdde317cfec" 
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.gwlb_subnet.id
  vpc_security_group_ids      = [aws_security_group.firewall_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.deployer.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Firewall is Healthy" > /var/www/html/index.html
              EOF

  tags = { Name = "inspection-appliance" }
}

resource "aws_lb_target_group_attachment" "gwlb_attach" {
  target_group_arn = aws_lb_target_group.gwlb_tg.arn
  target_id        = aws_instance.firewall.id
}

# Internet Gateway and Routing
resource "aws_internet_gateway" "security_igw" {
  vpc_id = aws_vpc.security_vpc.id
}

resource "aws_route_table" "security_rt" {
  vpc_id = aws_vpc.security_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.security_igw.id
  }
}

resource "aws_route_table_association" "security_assoc" {
  subnet_id      = aws_subnet.gwlb_subnet.id
  route_table_id = aws_route_table.security_rt.id
}

resource "aws_vpc_endpoint_service" "gwlb_service" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.security_gwlb.arn]
}

# --- NEW: THE MISSING PIECE ---
resource "aws_lb_listener" "gwlb_listener" {
  load_balancer_arn = aws_lb.security_gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gwlb_tg.arn
  }
}
# ------------------------------

output "gwlb_service_name" {
  value = aws_vpc_endpoint_service.gwlb_service.service_name
}