data "aws_ami" "ubuntu" {
  provider = aws.use1

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
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

# ==================== SSM IAM ROLE ====================
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

resource "aws_iam_role_policy_attachment" "ssm_core" {
  provider   = aws.use1
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  provider = aws.use1
  name     = "${var.project_name}-ssm-profile"
  role     = aws_iam_role.ssm_role.name
}

# ==================== EC2 INSTANCES ====================

# Vote + Result (Public Subnets)
resource "aws_instance" "vote" {
  provider = aws.use1
  for_each = aws_subnet.public

  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  subnet_id            = each.value.id
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              # Ensure SSM Agent is installed and running via Snap
              sudo snap install amazon-ssm-agent --classic || echo "SSM Agent already installed"

              # Start and enable the agent
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF


  tags = {
    Name = "${var.project_name}-vote-${each.key}"
    Role = "vote-result"
  }
}

# Redis + Worker (Private Subnets)
resource "aws_instance" "worker" {
  provider = aws.use1
  for_each = aws_subnet.private

  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  subnet_id            = each.value.id
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              # Ensure SSM Agent is installed and running via Snap
              sudo snap install amazon-ssm-agent --classic || echo "SSM Agent already installed"

              # Start and enable the agent
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name = "${var.project_name}-worker-${each.key}"
    Role = "redis-worker"
  }
}

# PostgreSQL Primary (AZ1)
resource "aws_instance" "postgres_primary" {
  provider = aws.use1

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.db[var.azs[0]].id # Explicit AZ1

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              # Ensure SSM Agent is installed and running via Snap
              sudo snap install amazon-ssm-agent --classic || echo "SSM Agent already installed"

              # Start and enable the agent
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name = "${var.project_name}-postgres-primary"
    Role = "postgres-primary"
  }
}

# PostgreSQL Standby (AZ2)
resource "aws_instance" "postgres_standby" {
  provider = aws.use1

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.db[var.azs[1]].id # Explicit AZ2

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              # Ensure SSM Agent is installed and running via Snap
              sudo snap install amazon-ssm-agent --classic || echo "SSM Agent already installed"

              # Start and enable the agent
              sudo snap enable amazon-ssm-agent
              sudo snap start amazon-ssm-agent
              EOF

  tags = {
    Name = "${var.project_name}-postgres-standby"
    Role = "postgres-standby"
  }
}
