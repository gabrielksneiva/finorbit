##############################################
# 📁 /infra/services/main.tf
# Lambdas, Triggers e Integração com RDS
##############################################

locals {
  name_prefix = "finorbit-${var.env}"
}

# =======================
# 🧩 Lambdas
# =======================
resource "aws_lambda_function" "producer" {
  function_name    = "${local.name_prefix}-producer"
  role             = data.terraform_remote_state.infra.outputs.lambda_role_arn
  package_type     = "Image"
  image_uri        = "${data.terraform_remote_state.infra.outputs.ecr_producer_repo_url}:${var.producer_image_tag}"
  source_code_hash = base64sha256(var.producer_image_tag)

  environment {
    variables = {
      SNS_TOPIC_ARN = data.terraform_remote_state.infra.outputs.sns_topic_arn
    }
  }
}

resource "aws_lambda_function" "consumer_deposit" {
  function_name    = "${local.name_prefix}-consumer-deposit"
  role             = data.terraform_remote_state.infra.outputs.lambda_role_arn
  package_type     = "Image"
  image_uri        = "${data.terraform_remote_state.infra.outputs.ecr_consumer_repo_url}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)

  environment {
    variables = {
      DB_HOST = data.terraform_remote_state.infra.outputs.db_host
      DB_USER = data.terraform_remote_state.infra.outputs.db_user
      DB_PASS = data.terraform_remote_state.infra.outputs.db_pass
      DB_NAME = data.terraform_remote_state.infra.outputs.db_name
    }
  }

  dynamic "vpc_config" {
    for_each = length(data.terraform_remote_state.infra.outputs.private_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = data.terraform_remote_state.infra.outputs.private_subnet_ids
      security_group_ids = [data.terraform_remote_state.infra.outputs.default_sg_id]
    }
  }
}

resource "aws_lambda_function" "consumer_withdraw" {
  function_name    = "${local.name_prefix}-consumer-withdraw"
  role             = data.terraform_remote_state.infra.outputs.lambda_role_arn
  package_type     = "Image"
  image_uri        = "${data.terraform_remote_state.infra.outputs.ecr_consumer_repo_url}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)

  environment {
    variables = {
      DB_HOST = data.terraform_remote_state.infra.outputs.db_host
      DB_USER = data.terraform_remote_state.infra.outputs.db_user
      DB_PASS = data.terraform_remote_state.infra.outputs.db_pass
      DB_NAME = data.terraform_remote_state.infra.outputs.db_name
    }
  }

  dynamic "vpc_config" {
    for_each = length(data.terraform_remote_state.infra.outputs.private_subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = data.terraform_remote_state.infra.outputs.private_subnet_ids
      security_group_ids = [data.terraform_remote_state.infra.outputs.default_sg_id]
    }
  }
}

# =======================
# 🔗 Triggers SQS
# =======================
resource "aws_lambda_event_source_mapping" "deposit_trigger" {
  event_source_arn = local.queues.deposit
  function_name    = aws_lambda_function.consumer_deposit.arn
  batch_size       = 1
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "withdraw_trigger" {
  event_source_arn = local.queues.withdraw
  function_name    = aws_lambda_function.consumer_withdraw.arn
  batch_size       = 1
  enabled          = true
}
