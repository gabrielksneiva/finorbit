locals {
  name_prefix = "finorbit-${var.env}"
}

# =======================
# 🧩 Lambdas
# =======================
resource "aws_lambda_function" "producer" {
  function_name   = "${local.name_prefix}-producer"
  role            = local.lambda_role_arn
  package_type    = "Image"
  image_uri       = "${local.repositories.producer}:${var.producer_image_tag}"
  source_code_hash = base64sha256(var.producer_image_tag)

  environment {
    variables = {
      SNS_TOPIC_ARN = data.terraform_remote_state.infra.outputs.sns_topic_arn
    }
  }
}

resource "aws_lambda_function" "consumer_deposit" {
  function_name   = "${local.name_prefix}-consumer-deposit"
  role            = local.lambda_role_arn
  package_type    = "Image"
  image_uri       = "${local.repositories.consumer}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)

  environment {
    variables = {
      DB_HOST = data.terraform_remote_state.infra.outputs.db_host
      DB_USER = data.terraform_remote_state.infra.outputs.db_user
      DB_PASS = data.terraform_remote_state.infra.outputs.db_pass
      DB_NAME = data.terraform_remote_state.infra.outputs.db_name
    }
  }
}

resource "aws_lambda_function" "consumer_withdraw" {
  function_name   = "${local.name_prefix}-consumer-withdraw"
  role            = local.lambda_role_arn
  package_type    = "Image"
  image_uri       = "${local.repositories.consumer}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)

  environment {
    variables = {
      DB_HOST = data.terraform_remote_state.infra.outputs.db_host
      DB_USER = data.terraform_remote_state.infra.outputs.db_user
      DB_PASS = data.terraform_remote_state.infra.outputs.db_pass
      DB_NAME = data.terraform_remote_state.infra.outputs.db_name
    }
  }
}

# Triggers
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

# =======================
# 🌐 API Gateway
# =======================

resource "aws_apigatewayv2_api" "finorbit_api" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "producer_integration" {
  api_id                 = aws_apigatewayv2_api.finorbit_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "transactions_route" {
  api_id    = aws_apigatewayv2_api.finorbit_api.id
  route_key = "POST /transaction"
  target    = "integrations/${aws_apigatewayv2_integration.producer_integration.id}"
}

resource "aws_lambda_permission" "allow_apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.finorbit_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.finorbit_api.id
  name        = "prod"
  auto_deploy = true
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_stage.prod.invoke_url
  description = "URL pública do API Gateway (stage prod)"
}
