##############################################
# 📁 /services/main.tf
# Define apenas os serviços que mudam em deploys:
# Lambdas, triggers, integrações e permissões.
# A infra base (IAM, ECR, SNS, SQS, API Gateway, etc)
# é gerenciada em /infra.
##############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "finorbit-terraform-state" # 🧠 ajuste para seu bucket
    key            = "services/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

# =======================
# 📡 Importa estado da infra
# =======================
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "finorbit-terraform-state"   # 🧠 mesmo bucket da infra
    key    = "infra/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  name_prefix = "finorbit-${var.env}"
}

# =======================
# 🧩 BLOCO 1 — Lambdas
# =======================
resource "aws_lambda_function" "producer" {
  function_name = "${local.name_prefix}-producer"
  role          = data.terraform_remote_state.infra.outputs.lambda_role_arn
  package_type  = "Image"

  image_uri = "${data.terraform_remote_state.infra.outputs.ecr_producer_repo_url}:${var.producer_image_tag}"
  source_code_hash = base64sha256(var.producer_image_tag)

  # evita recriação desnecessária
  lifecycle {
    ignore_changes = [environment, tags]
  }
}

resource "aws_lambda_function" "consumer_deposit" {
  function_name = "${local.name_prefix}-consumer-deposit"
  role          = data.terraform_remote_state.infra.outputs.lambda_role_arn
  package_type  = "Image"

  image_uri = "${data.terraform_remote_state.infra.outputs.ecr_consumer_repo_url}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)

  lifecycle {
    ignore_changes = [environment, tags]
  }
}

resource "aws_lambda_function" "consumer_withdraw" {
  function_name = "${local.name_prefix}-consumer-withdraw"
  role          = data.terraform_remote_state.infra.outputs.lambda_role_arn
  package_type  = "Image"

  image_uri = "${data.terraform_remote_state.infra.outputs.ecr_consumer_repo_url}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)

  lifecycle {
    ignore_changes = [environment, tags]
  }
}

# =======================
# 🔔 BLOCO 2 — Permissões e triggers
# =======================
# Liga as consumers às filas
resource "aws_lambda_event_source_mapping" "deposit_trigger" {
  event_source_arn = data.terraform_remote_state.infra.outputs.sqs_deposit_arn
  function_name    = aws_lambda_function.consumer_deposit.arn
  batch_size       = 1
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "withdraw_trigger" {
  event_source_arn = data.terraform_remote_state.infra.outputs.sqs_withdraw_arn
  function_name    = aws_lambda_function.consumer_withdraw.arn
  batch_size       = 1
  enabled          = true
}

# Permite que o API Gateway invoque o producer
resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.terraform_remote_state.infra.outputs.api_id}/*"
}

# =======================
# 🌐 BLOCO 3 — API Gateway Integration
# =======================
resource "aws_apigatewayv2_integration" "finorbit_integration" {
  api_id                 = data.terraform_remote_state.infra.outputs.api_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "transaction_route" {
  api_id    = data.terraform_remote_state.infra.outputs.api_id
  route_key = "POST /transaction"
  target    = "integrations/${aws_apigatewayv2_integration.finorbit_integration.id}"
}

# =======================
# 📊 BLOCO 4 — CloudWatch
# =======================
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    producer         = aws_lambda_function.producer.function_name
    consumer_deposit = aws_lambda_function.consumer_deposit.function_name
    consumer_withdraw = aws_lambda_function.consumer_withdraw.function_name
  }

  alarm_name          = "${local.name_prefix}-${each.key}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [data.terraform_remote_state.infra.outputs.sns_alerts_arn]
  dimensions = { FunctionName = each.value }
}

# =======================
# 📤 BLOCO 5 — Outputs
# =======================
output "api_url" {
  value = "${data.terraform_remote_state.infra.outputs.api_url_base}/transaction"
}

output "producer_lambda_arn" {
  value = aws_lambda_function.producer.arn
}

output "consumer_deposit_lambda_arn" {
  value = aws_lambda_function.consumer_deposit.arn
}

output "consumer_withdraw_lambda_arn" {
  value = aws_lambda_function.consumer_withdraw.arn
}
