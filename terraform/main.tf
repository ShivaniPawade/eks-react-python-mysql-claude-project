# ─────────────────────────────────────────────────────────────────
# terraform/main.tf  —  VPC + EKS + RDS for 3-tier app
# Usage:
#   terraform init
#   terraform plan -var-file=terraform.tfvars
#   terraform apply -var-file=terraform.tfvars
# ─────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — create the S3 bucket + DynamoDB table first
  backend "s3" {
    bucket         = "shortbust-backend-bucket"
    key            = "3tier-app/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile = true
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

# ── Data ────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {}

# ── VPC ─────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # save cost in dev; use false for prod
  enable_dns_hostnames = true

  # EKS requires these tags on subnets
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.project}-eks" = "owned"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${var.project}-eks" = "owned"
  }

  tags = local.common_tags
}

# ── EKS ─────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.30"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    app = {
      instance_types = ["c7i-flex.large"]

      ami_type = "AL2023_x86_64_STANDARD"

      min_size     = 1
      max_size     = 2
      desired_size = 2

      labels = {
        role = "app"
      }
    }
  }

  tags = local.common_tags
}

# ── RDS Security Group ───────────────────────────────────────────
resource "aws_security_group" "rds" {
  name   = "${var.project}-rds-sg"
  vpc_id = module.vpc.vpc_id

  # Only allow MySQL from EKS nodes (not public)
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# ── RDS Subnet Group ────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet"
  subnet_ids = module.vpc.private_subnets
  tags       = local.common_tags
}

# ── RDS MySQL ───────────────────────────────────────────────────
resource "aws_db_instance" "mysql" {
  identifier        = "${var.project}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"   # cheap for dev
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot = true          # set false for prod
  publicly_accessible = false         # never expose RDS publicly

  tags = local.common_tags
}

# ── ECR repos for our images ─────────────────────────────────────
resource "aws_ecr_repository" "backend" {
  name                 = "backend"
  image_tag_mutability = "MUTABLE"
  tags                 = local.common_tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "frontend"
  image_tag_mutability = "MUTABLE"
  tags                 = local.common_tags
}

# ── Locals ───────────────────────────────────────────────────────
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── Outputs ──────────────────────────────────────────────────────
output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "rds_endpoint" {
  value     = aws_db_instance.mysql.address
  sensitive = true
}

output "ecr_backend_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}
