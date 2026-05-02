# ==================== OUTPUTS ====================

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = { for k, v in aws_subnet.public : k => v.id }
}

output "private_subnets" {
  value = { for k, v in aws_subnet.private : k => v.id }
}

output "db_subnets" {
  value = { for k, v in aws_subnet.db : k => v.id }
}

output "ssm_profile_name" {
  value = aws_iam_instance_profile.ssm_profile.name
}

# ==================== INSTANCE IDs ====================

output "vote_instances" {
  description = "Vote instances IDs (one per AZ)"
  value       = { for k, v in aws_instance.vote : k => v.id }
}

output "worker_instances" {
  description = "Worker instances IDs (one per AZ)"
  value       = { for k, v in aws_instance.worker : k => v.id }
}

output "postgres_primary_id" {
  value = aws_instance.postgres_primary.id
}

output "postgres_standby_id" {
  value = aws_instance.postgres_standby.id
}

# ==================== LOAD BALANCER ====================

output "load_balancer_dns" {
  description = "Load Balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "vote_app_url" {
  description = "Direct URL to access your Vote app via Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

# ==================== SSM CONNECTION COMMANDS ====================

output "ssm_commands" {
  description = "Ready-to-copy SSM connection commands"
  value = {
    vote_az1         = "aws ssm start-session --target ${aws_instance.vote[var.azs[0]].id} --region us-east-2"
    vote_az2         = "aws ssm start-session --target ${aws_instance.vote[var.azs[1]].id} --region us-east-2"
    worker_az1       = "aws ssm start-session --target ${aws_instance.worker[var.azs[0]].id} --region us-east-2"
    worker_az2       = "aws ssm start-session --target ${aws_instance.worker[var.azs[1]].id} --region us-east-2"
    postgres_primary = "aws ssm start-session --target ${aws_instance.postgres_primary.id} --region us-east-2"
    postgres_standby = "aws ssm start-session --target ${aws_instance.postgres_standby.id} --region us-east-2"
  }
}

# ==================== PRIVATE IPs ====================

output "private_ips" {
  description = "Private IP addresses of all instances"
  value = {
    vote_az1         = aws_instance.vote[var.azs[0]].private_ip
    vote_az2         = aws_instance.vote[var.azs[1]].private_ip
    worker_az1       = aws_instance.worker[var.azs[0]].private_ip
    worker_az2       = aws_instance.worker[var.azs[1]].private_ip
    postgres_primary = aws_instance.postgres_primary.private_ip
    postgres_standby = aws_instance.postgres_standby.private_ip
  }
}
