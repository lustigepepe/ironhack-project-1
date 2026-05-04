# AWS VPC Infrastructure with Load Balancer

A production-ready AWS infrastructure deployed using **Terraform** and configured with **Ansible** via **AWS Systems Manager (SSM)**.

## Overview

This project provisions a highly available VPC across **two Availability Zones** in AWS, including a public-facing **Application Load Balancer (ALB)**, private subnets, and supporting resources. Configuration management and application deployment are handled through Ansible playbooks executed via SSM.

## Architecture

- **VPC** with CIDR `10.0.0.0/16`
- **2 Availability Zones** for high availability
- **Public Subnets** (one per AZ) – used by the Load Balancer
- **Private Subnets** (one per AZ) – for application servers / EC2 instances
- **Internet Gateway** + NAT Gateways for outbound internet access
- **Application Load Balancer (ALB)** with HTTPS/HTTP listeners
- **EC2 Instances** in an Auto Scaling Group (or standalone) behind the ALB
- **S3 Buckets** for static assets, backups, and Ansible artifact storage
- **SSM (Systems Manager)** for secure, agent-based configuration and deployments

## Technologies Used

| Tool / Service                | Purpose                                   |
| ----------------------------- | ----------------------------------------- |
| **Terraform**                 | Infrastructure as Code                    |
| **Ansible**                   | Configuration Management & App Deployment |
| **AWS SSM**                   | Secure remote execution & orchestration   |
| **Application Load Balancer** | Traffic distribution & SSL termination    |
| **Amazon S3**                 | Static files, backups & artifacts         |
| **VPC**                       | Isolated networking                       |
| **EC2 + Auto Scaling**        | Compute resources                         |

## Features

- Multi-AZ high availability
- Private EC2 instances (no public IPs)
- Secure SSH access via SSM Session Manager (no bastion host needed)
- Ansible playbooks delivered and executed through SSM
- Infrastructure state stored in S3 backend (recommended)
- Modular Terraform code

## Prerequisites

- AWS CLI configured with proper credentials
- Terraform ≥ 1.5
- Ansible ≥ 10.x
- `terraform.tfvars` file with your configuration
- Appropriate IAM permissions for Terraform and SSM

## Deployment Steps

### 1. Infrastructure (Terraform)

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```
