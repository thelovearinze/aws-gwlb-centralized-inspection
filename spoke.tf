# 1. The Consumer VPC (The Spoke)
resource "aws_vpc" "spoke_vpc" {
  cidr_block           = "198.19.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "spoke-app-vpc" }
}

# 2. Subnet for the GWLBE
resource "aws_subnet" "spoke_gwlbe_subnet" {
  vpc_id            = aws_vpc.spoke_vpc.id
  cidr_block        = "198.19.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "spoke-gwlbe-subnet" }
}

# 3. The GWLB Endpoint
resource "aws_vpc_endpoint" "gwlbe" {
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_id            = aws_vpc.spoke_vpc.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.spoke_gwlbe_subnet.id]
  tags = { Name = "spoke-gwlb-endpoint" }
}

# 4. Subnet for the Application
resource "aws_subnet" "spoke_app_subnet" {
  vpc_id            = aws_vpc.spoke_vpc.id
  cidr_block        = "198.19.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "spoke-app-subnet" }
}

# 5. Security Group for the App
resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.spoke_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. The Application Instance
resource "aws_instance" "app_server" {
  ami                         = "ami-0c7217cdde317cfec" 
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.spoke_app_subnet.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true 
  key_name                    = aws_key_pair.deployer.key_name

  tags = { Name = "spoke-app-server" }
}

# 7. Internet Gateway for the Spoke
resource "aws_internet_gateway" "spoke_igw" {
  vpc_id = aws_vpc.spoke_vpc.id
  tags   = { Name = "spoke-igw" }
}

# 8. Route Table (THE FIX: Split Routing)
resource "aws_route_table" "spoke_app_rt" {
  vpc_id = aws_vpc.spoke_vpc.id

  # 1. SSH/General Traffic -> Goes to Internet Gateway (Keeps you connected)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.spoke_igw.id
  }

  # 2. The "Article Proof" Traffic -> Goes to Inspection Hub
  route {
    cidr_block      = "8.8.8.8/32"
    vpc_endpoint_id = aws_vpc_endpoint.gwlbe.id
  }

  tags = { Name = "spoke-app-rt" }
}

# 9. Associate the Route Table
resource "aws_route_table_association" "spoke_app_assoc" {
  subnet_id      = aws_subnet.spoke_app_subnet.id
  route_table_id = aws_route_table.spoke_app_rt.id
}