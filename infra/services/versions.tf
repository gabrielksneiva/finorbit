terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket  = "finorbit-terraform-state"
    key     = "infra/services/terraform.tfstate"
    region  = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}
