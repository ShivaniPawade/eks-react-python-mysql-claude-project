variable "region" {
  default = "us-east-1"
}

variable "project" {
  default = "myapp"
}

variable "environment" {
  default = "dev"
}

variable "db_name" {
  default = "appdb"
}

variable "db_user" {
  default = "admin"
}

variable "db_password" {
  description = "RDS master password — set in terraform.tfvars, never commit"
  sensitive   = true
}
