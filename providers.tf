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