terraform {
  # minimum allowed version
  required_version = ">= 0.12.24"

  backend "s3" {
    bucket         = "moshinde-terraform-eks"
    key            = "ms/deploy-eks"
    region         = "us-east-1"
    profile = "personal"
  }
}

provider "aws" {
  profile = "personal"
  shared_credentials_file = "~/.aws/credentials"
}