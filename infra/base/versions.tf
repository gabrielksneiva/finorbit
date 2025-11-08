terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # ← troque para 6.x
    }
  }

  backend "s3" {
    bucket = "finorbit-terraform-state"
    key    = "infra/base/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}
