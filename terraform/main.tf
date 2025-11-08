# =======================
# 🔧 BLOCO 0 — Variáveis e prefixos
# =======================
variable "env" {
  type    = string
  default = "dev"
}

variable "create_rds" {
  type    = bool
  default = true
}

provider "aws" {
  region = "us-east-1"
}

locals {
  name_prefix = "finorbit-${var.env}"
}

# =======================
# 🧠 BLOCO 1 — IAM Role para Lambdas
# =======================
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_rds_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_ecr_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# =======================
# 🪧 BLOCO 2 — SNS Topics
# =======================
resource "aws_sns_topic" "transactions" {
  name = "${local.name_prefix}-transactions"
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

# =======================
# 📬 BLOCO 3 — SQS Queues
# =======================
resource "aws_sqs_queue" "transactions_deposit_queue" {
  name = "${local.name_prefix}-deposit-queue"
}

resource "aws_sqs_queue" "transactions_withdraw_queue" {
  name = "${local.name_prefix}-withdraw-queue"
}

# SNS → SQS subscriptions
resource "aws_sns_topic_subscription" "sns_to_deposit_sqs" {
  topic_arn    = aws_sns_topic.transactions.arn
  protocol     = "sqs"
  endpoint     = aws_sqs_queue.transactions_deposit_queue.arn
  filter_policy = jsonencode({ type = ["deposit"] })
}

resource "aws_sns_topic_subscription" "sns_to_withdraw_sqs" {
  topic_arn    = aws_sns_topic.transactions.arn
  protocol     = "sqs"
  endpoint     = aws_sqs_queue.transactions_withdraw_queue.arn
  filter_policy = jsonencode({ type = ["withdraw"] })
}

# Permitir SNS publicar nas filas
resource "aws_sqs_queue_policy" "allow_sns_deposit" {
  queue_url = aws_sqs_queue.transactions_deposit_queue.id
  policy    = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "SQS:SendMessage"
      Resource  = aws_sqs_queue.transactions_deposit_queue.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.transactions.arn } }
    }]
  })
}

resource "aws_sqs_queue_policy" "allow_sns_withdraw" {
  queue_url = aws_sqs_queue.transactions_withdraw_queue.id
  policy    = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "SQS:SendMessage"
      Resource  = aws_sqs_queue.transactions_withdraw_queue.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.transactions.arn } }
    }]
  })
}

# =======================
# 📦 BLOCO 4 — ECR Repositories
# =======================
resource "aws_ecr_repository" "consumer_repo" {
  name = "${local.name_prefix}-consumer"
  force_delete = true
}

resource "aws_ecr_repository" "producer_repo" {
  name = "${local.name_prefix}-producer"
  force_delete = true
}

resource "aws_ecr_repository_policy" "allow_lambda_consumer" {
  repository = aws_ecr_repository.consumer_repo.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaPull"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"]
    }]
  })
}

resource "aws_ecr_repository_policy" "allow_lambda_producer" {
  repository = aws_ecr_repository.producer_repo.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaPull"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"]
    }]
  })
}

# =======================
# 🧩 BLOCO 5 — Lambdas
# =======================
resource "aws_lambda_function" "producer" {
  function_name = "${local.name_prefix}-producer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = aws_ecr_repository.producer_repo.repository_url
}

resource "aws_lambda_function" "consumer_deposit" {
  function_name = "${local.name_prefix}-consumer-deposit"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = aws_ecr_repository.consumer_repo.repository_url
}

resource "aws_lambda_function" "consumer_withdraw" {
  function_name = "${local.name_prefix}-consumer-withdraw"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = aws_ecr_repository.consumer_repo.repository_url
}

# Event Source Mappings
resource "aws_lambda_event_source_mapping" "deposit_trigger" {
  event_source_arn = aws_sqs_queue.transactions_deposit_queue.arn
  function_name    = aws_lambda_function.consumer_deposit.arn
  batch_size       = 1
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "withdraw_trigger" {
  event_source_arn = aws_sqs_queue.transactions_withdraw_queue.arn
  function_name    = aws_lambda_function.consumer_withdraw.arn
  batch_size       = 1
  enabled          = true
}

# =======================
# 🌐 BLOCO 6 — API Gateway
# =======================
resource "aws_apigatewayv2_api" "finorbit_api" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "finorbit_integration" {
  api_id                 = aws_apigatewayv2_api.finorbit_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "transaction_route" {
  api_id    = aws_apigatewayv2_api.finorbit_api.id
  route_key = "POST /transaction"
  target    = "integrations/${aws_apigatewayv2_integration.finorbit_integration.id}"
}

resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.finorbit_api.execution_arn}/*"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.finorbit_api.id
  name        = "prod"
  auto_deploy = true
}

# =======================
# 💾 BLOCO 7 — Banco RDS (opcional)
# =======================
data "aws_vpc" "default" { default = true }

resource "aws_security_group" "finorbit_db_sg" {
  count  = var.create_rds ? 1 : 0
  name   = "${local.name_prefix}-db-sg"
  vpc_id = data.aws_vpc.default.id
}

resource "aws_db_instance" "finorbit_db" {
  count = var.create_rds ? 1 : 0
  identifier = "${local.name_prefix}-db"
  engine     = "postgres"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  username = "finorbit_admin"
  password = "Finorbit123!"
  db_name = "finorbit"
  publicly_accessible = true
  skip_final_snapshot = true
  vpc_security_group_ids = var.create_rds ? [aws_security_group.finorbit_db_sg[0].id] : []
}

# =======================
# 🌟 BLOCO 8 — CloudWatch Alarms & Dashboard
# =======================
resource "aws_cloudwatch_metric_alarm" "producer_lambda_errors" {
  alarm_name          = "${local.name_prefix}-producer-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = { FunctionName = aws_lambda_function.producer.function_name }
}

resource "aws_cloudwatch_metric_alarm" "consumer_deposit_lambda_errors" {
  alarm_name          = "${local.name_prefix}-consumer-deposit-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = { FunctionName = aws_lambda_function.consumer_deposit.function_name }
}

resource "aws_cloudwatch_metric_alarm" "consumer_withdraw_lambda_errors" {
  alarm_name          = "${local.name_prefix}-consumer-withdraw-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = { FunctionName = aws_lambda_function.consumer_withdraw.function_name }
}

resource "aws_cloudwatch_dashboard" "finorbit_dashboard" {
  dashboard_name = "${local.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0, y = 0, width = 12, height = 6,
        properties = {
          metrics = [["AWS/Lambda","Errors","FunctionName",aws_lambda_function.producer.function_name]]
          region  = "us-east-1"
          title   = "Producer Lambda Errors"
        }
      },
      {
        type = "metric",
        x = 0, y = 7, width = 12, height = 6,
        properties = {
          metrics = [["AWS/Lambda","Errors","FunctionName",aws_lambda_function.consumer_deposit.function_name]]
          region  = "us-east-1"
          title   = "Consumer Deposit Lambda Errors"
        }
      }
    ]
  })
}

# =======================
# 📤 OUTPUTS
# =======================
output "api_url" { value = "${aws_apigatewayv2_stage.prod.invoke_url}/transaction" }
output "deposit_queue_url" { value = aws_sqs_queue.transactions_deposit_queue.url }
output "withdraw_queue_url" { value = aws_sqs_queue.transactions_withdraw_queue.url }
output "alerts_sns_topic_arn" { value = aws_sns_topic.alerts.arn }
output "cloudwatch_dashboard_url" { value = "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=${aws_cloudwatch_dashboard.finorbit_dashboard.dashboard_name}" }
