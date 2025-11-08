data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "finorbit-terraform-state"
    key    = "infra/base/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  lambda_role_arn = data.terraform_remote_state.infra.outputs.lambda_role_arn

  repositories = {
    consumer = data.terraform_remote_state.infra.outputs.ecr_consumer_repo_url
    producer = data.terraform_remote_state.infra.outputs.ecr_producer_repo_url
  }

  queues = {
    deposit  = data.terraform_remote_state.infra.outputs.sqs_deposit_arn
    withdraw = data.terraform_remote_state.infra.outputs.sqs_withdraw_arn
  }
}
