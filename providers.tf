terraform {
  # minimum allowed version

  backend "s3" {
    bucket         = "moshinde-terraform-eks-sandbox"
    key            = "ms/deploy-eks-sandbox"
    region         = "us-east-1"
    profile = "sandbox"
  }

  required_providers {
    aws        = "~> 3.0"
    kubernetes = "~> 1.13"
    helm       = ">= 1.3.0"
  }
}

provider "aws" {
  profile = "sandbox"
  shared_credentials_file = "~/.aws/credentials"
  region = "us-east-1"
}