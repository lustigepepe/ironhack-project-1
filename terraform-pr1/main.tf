data "aws_ami" "ubuntu" {
  provider = aws.use1

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_region" "current" {
  provider = aws.use1
}

# ==================== VPC & IGW ====================
resource "aws_vpc" "main" {
  provider = aws.use1

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  provider = aws.use1
  vpc_id   = aws_vpc.main.id
  tags     = { Name = "${var.project_name}-igw" }
}

# ==================== SUBNETS ====================

# Public Subnets - Vote + Result
resource "aws_subnet" "public" {
  provider = aws.use1
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, each.value)
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${each.key}" }
}

# Private Subnets - Redis + Worker
resource "aws_subnet" "private" {
  provider = aws.use1
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, each.value + 10)
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-private-${each.key}" }
}

# Private Subnets - PostgreSQL
resource "aws_subnet" "db" {
  provider = aws.use1
  for_each = { for idx, az in var.azs : az => idx }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, each.value + 20)
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-db-${each.key}" }
}

# ==================== NAT GATEWAY ====================
resource "aws_eip" "nat" {
  provider = aws.use1
  domain   = "vpc"
}

resource "aws_nat_gateway" "nat" {
  provider      = aws.use1
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.azs[0]].id

  tags = { Name = "${var.project_name}-nat" }

}

# ==================== ROUTE TABLES ====================
resource "aws_route_table" "public" {
  provider = aws.use1
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table" "private" {
  provider = aws.use1
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.project_name}-private-rt" }

}

# ==================== ROUTE TABLE ASSOCIATIONS ====================
resource "aws_route_table_association" "public" {
  provider       = aws.use1
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  provider       = aws.use1
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db" {
  provider       = aws.use1
  for_each       = aws_subnet.db
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ==================== S3 GATEWAY VPC ENDPOINT ====================

resource "aws_vpc_endpoint" "s3" {
  provider          = aws.use1
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id
  ]


  tags = {
    Name      = "${var.project_name}-s3-endpoint"
    Purpose   = "Access S3 privately from VPC"
    ManagedBy = "Terraform"
  }
}

# ==================== SSM INTERFACE ENDPOINTS (for Private Subnets) ====================
# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoint_sg" {
  provider = aws.use1
  name     = "${var.project_name}-vpc-endpoints-sg"
  vpc_id   = aws_vpc.main.id

  # === Allow HTTP (80) and HTTPS (443) from within the VPC ===
  ingress {
    description = "Allow HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Allow HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-vpc-endpoint-sg" }
}

# SSM Interface Endpoints
locals {
  ssm_endpoints = [
    "com.amazonaws.${data.aws_region.current.id}.ssm",
    "com.amazonaws.${data.aws_region.current.id}.ssmmessages",
    "com.amazonaws.${data.aws_region.current.id}.ec2messages"
  ]
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(local.ssm_endpoints)

  provider            = aws.use1
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true


  subnet_ids = [
    for az in var.azs : aws_subnet.private[az].id
  ]
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]

  tags = {
    Name      = "${var.project_name}-${split(".", each.value)[3]}-endpoint"
    Purpose   = "SSM for private subnets"
    ManagedBy = "Terraform"
  }
}

# ==================== SSM IAM ROLE + S3 PERMISSIONS ====================

resource "aws_iam_role" "ssm_role" {
  provider = aws.use1
  name     = "${var.project_name}-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# SSM Core Policy (required for Session Manager, Run Command, State Manager, etc.)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  provider   = aws.use1
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom S3 Policy - Allows access to your Ansible bucket
resource "aws_iam_policy" "ansible_ssm_bucket_access" {
  provider = aws.use1
  name     = "${var.project_name}-ansible-ssm-bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.ansible_ssm.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["${aws_s3_bucket.ansible_ssm.arn}/*"]
      }
    ]
  })
}

# Attach S3 policy to the role
resource "aws_iam_role_policy_attachment" "ansible_ssm_access" {
  provider   = aws.use1
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.ansible_ssm_bucket_access.arn
}

# Instance Profile - Used by ALL your EC2 instances
resource "aws_iam_instance_profile" "ssm_profile" {
  provider = aws.use1
  name     = "${var.project_name}-ssm-profile"
  role     = aws_iam_role.ssm_role.name
}


# ==================== ANSIBLE SSM S3 BUCKET ====================
resource "aws_s3_bucket" "ansible_ssm" {
  provider      = aws.use1
  bucket        = "${var.project_name}-ansible-ssm-bucket"
  force_destroy = true
  tags = {
    Name      = "${var.project_name}-ansible-ssm"
    Purpose   = "ansible-ssm-session-manager"
    ManagedBy = "Terraform"
  }
}


# Block public access (security best practice)
resource "aws_s3_bucket_public_access_block" "ansible_ssm" {
  provider = aws.use1
  bucket   = aws_s3_bucket.ansible_ssm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# ==================== SECURITY GROUPS FOR APPS ====================

# Public Apps (Vote + Result)
resource "aws_security_group" "public_app_sg" {
  provider = aws.use1
  name     = "${var.project_name}-public-app-sg"
  vpc_id   = aws_vpc.main.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Vote App"
  }

  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Result App"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-public-app-sg" }
}

# Private Apps (Worker + Redis)
resource "aws_security_group" "private_app_sg" {
  provider = aws.use1
  name     = "${var.project_name}-private-app-sg"
  vpc_id   = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.public_app_sg.id]
    description     = "Allow Vote/Result to Redis"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Allow internal private traffic"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-private-app-sg" }
}

# PostgreSQL
resource "aws_security_group" "db_sg" {
  provider = aws.use1
  name     = "${var.project_name}-db-sg"
  vpc_id   = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.public_app_sg.id, aws_security_group.private_app_sg.id]
    description     = "Allow apps to Postgres"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}
# ==================== EC2 INSTANCES ====================

# Vote + Result (Public)
resource "aws_instance" "vote" {
  provider = aws.use1
  for_each = aws_subnet.public

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = each.value.id
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.public_app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo snap install amazon-ssm-agent --classic || true
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name    = "${var.project_name}-vote-${each.key}"
    Role    = "vote-result"
    Project = var.project_name
  }
}

# Redis + Worker (Private Subnets)
resource "aws_instance" "worker" {
  provider = aws.use1
  for_each = aws_subnet.private

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = each.value.id
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo snap install amazon-ssm-agent --classic || true
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name    = "${var.project_name}-worker-${each.key}"
    Role    = "redis-worker"
    Project = var.project_name
  }
}

# PostgreSQL Primary
resource "aws_instance" "postgres_primary" {
  provider = aws.use1

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.db[var.azs[0]].id
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo snap install amazon-ssm-agent --classic || true
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name    = "${var.project_name}-postgres-primary"
    Role    = "postgres-primary"
    Project = var.project_name
  }
}

# PostgreSQL Standby
resource "aws_instance" "postgres_standby" {
  provider = aws.use1

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.db[var.azs[1]].id
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo snap install amazon-ssm-agent --classic || true
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name    = "${var.project_name}-postgres-standby"
    Role    = "postgres-standby"
    Project = var.project_name
  }
}
# ==================== SECURITY GROUP FOR LOAD BALANCER ====================
resource "aws_security_group" "alb_sg" {
  provider = aws.use1
  name     = "${var.project_name}-alb-sg"
  vpc_id   = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ==================== APPLICATION LOAD BALANCER ====================
resource "aws_lb" "main" {
  provider           = aws.use1
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = { Name = "${var.project_name}-alb" }
}

# ==================== TARGET GROUP (for Docker port 8080) ====================
resource "aws_lb_target_group" "vote" {
  provider    = aws.use1
  name        = "${var.project_name}-vote-tg"
  port        = 8080 # ← Changed for Docker Compose
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-vote-tg" }
}

# ==================== LISTENER (HTTP) ====================
resource "aws_lb_listener" "http" {
  provider          = aws.use1
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote.arn
  }
}

# ==================== ATTACH VOTE INSTANCES ====================
resource "aws_lb_target_group_attachment" "vote" {
  for_each         = aws_instance.vote
  provider         = aws.use1
  target_group_arn = aws_lb_target_group.vote.arn
  target_id        = each.value.id
  port             = 8080
}
