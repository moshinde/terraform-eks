terraform {
  # minimum allowed version
  required_version = ">= 0.12.24"

  backend "s3" {
    bucket         = "moshinde-terraform-eks-sandbox"
    key            = "ms/deploy-eks"
    region         = "us-east-1"
    profile = "sandbox"
  }
}

provider "aws" {
  profile = "sandbox"
  shared_credentials_file = "~/.aws/credentials"
  region = "us-east-1"
}

data "aws_ami" "eks_node" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_version}*"]
  }

  most_recent = true
  owners      = ["329576768325"] # Core Services account
}