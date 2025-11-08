# =======================
# 🔧 BLOCO 0 — Variáveis de ambiente / prefixo
# =======================
variable "env" {
  type    = string
  default = "dev" # Pode ser dev, test, prod
}

resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  name_prefix = "finorbit-${var.env}-${random_id.suffix.hex}"
}

# =======================
# 🔧 BLOCO 1 — Provider AWS
# =======================
provider "aws" {
  region = "us-east-1"
}

# =======================
# 🪧 BLOCO 2 — SNS Topic
# =======================
resource "aws_sns_topic" "transactions" {
  name = "${local.name_prefix}-transactions"
}

# =======================
# 📬 BLOCO 3 — SQS Queues
# =======================
resource "aws_sqs_queue" "transactions_deposit_queue" {
  name = "${local.name_prefix}-transactions-deposit-queue"
}

resource "aws_sqs_queue" "transactions_withdraw_queue" {
  name = "${local.name_prefix}-transactions-withdraw-queue"
}

# =======================
# 🔗 BLOCO 4 — SNS → SQS Subscriptions com filtros
# =======================
resource "aws_sns_topic_subscription" "sns_to_deposit_sqs" {
  topic_arn = aws_sns_topic.transactions.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.transactions_deposit_queue.arn

  filter_policy = jsonencode({ type = ["deposit"] })
}

resource "aws_sns_topic_subscription" "sns_to_withdraw_sqs" {
  topic_arn = aws_sns_topic.transactions.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.transactions_withdraw_queue.arn

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
# 🧠 BLOCO 5 — IAM Role para Lambdas
# =======================
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# Permissões básicas e acesso
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_ecr_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "lambda_rds_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

# Permissão para Lambda publicar no SNS
resource "aws_sns_topic_policy" "allow_lambda_publish" {
  arn = aws_sns_topic.transactions.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaPublish"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.lambda_role.arn }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.transactions.arn
    }]
  })
}

# =======================
# 📦 BLOCO 6 — ECR Repositories
# =======================
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "consumer_repo" {
  name = "finorbit-consumer"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_repository" "producer_repo" {
  name = "finorbit-producer"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "consumer_policy" {
  repository = aws_ecr_repository.consumer_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove untagged images older than 1 day"
      selection = {
        tagStatus = "untagged"
        countType = "sinceImagePushed"
        countUnit = "days"
        countNumber = 1
      }
      action = { type = "expire" }
    }]
  })
}

# Política de ciclo de vida para o repositório do producer
resource "aws_ecr_lifecycle_policy" "producer_policy" {
  repository = aws_ecr_repository.producer_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Remove untagged images older than 1 day"
      selection = {
        tagStatus = "untagged"
        countType = "sinceImagePushed"
        countUnit = "days"
        countNumber = 1
      }
      action = { type = "expire" }
    }]
  })
}


# Política que permite Lambda puxar imagens
resource "aws_ecr_repository_policy" "allow_lambda_pull_consumer" {
  repository = aws_ecr_repository.consumer_repo.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaPull"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"]
    }]
  })
}

resource "aws_ecr_repository_policy" "allow_lambda_pull_producer" {
  repository = aws_ecr_repository.producer_repo.name
  policy     = jsonencode({
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
# 🧩 BLOCO 7 — Lambdas
# =======================
data "aws_ecr_image" "producer_latest" {
  repository_name = aws_ecr_repository.producer_repo.name
  image_tag       = "latest"
}

resource "aws_lambda_function" "producer" {
  function_name = "${local.name_prefix}-producer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.producer_repo.repository_url}@${data.aws_ecr_image.producer_latest.image_digest}"
  timeout       = 10

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = { SNS_TOPIC_ARN = aws_sns_topic.transactions.arn }
  }

  depends_on = [aws_ecr_repository.producer_repo]
}

data "aws_ecr_image" "consumer_latest" {
  repository_name = aws_ecr_repository.consumer_repo.name
  image_tag       = "latest"
}

resource "aws_lambda_function" "consumer_deposit" {
  function_name = "${local.name_prefix}-consumer-deposit"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.consumer_repo.repository_url}@${data.aws_ecr_image.consumer_latest.image_digest}"
  timeout       = 10

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.transactions_deposit_queue.url
      DB_HOST   = aws_db_instance.finorbit_db[0].address
      DB_USER   = "finorbit_admin"
      DB_PASS   = "Finorbit123!"
      DB_NAME   = "finorbit"
      TX_TYPE   = "deposit"
    }
  }

  depends_on = [aws_db_instance.finorbit_db]
}

resource "aws_lambda_function" "consumer_withdraw" {
  function_name = "${local.name_prefix}-consumer-withdraw"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.consumer_repo.repository_url}@${data.aws_ecr_image.consumer_latest.image_digest}"
  timeout       = 10

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.transactions_withdraw_queue.url
      DB_HOST   = aws_db_instance.finorbit_db[0].address
      DB_USER   = "finorbit_admin"
      DB_PASS   = "Finorbit123!"
      DB_NAME   = "finorbit"
      TX_TYPE   = "withdraw"
    }
  }

  depends_on = [aws_db_instance.finorbit_db]
}

# =======================
# 🔁 BLOCO 8 — Event Source Mappings
# =======================
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
# 🌐 BLOCO 9 — API Gateway
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
  depends_on  = [aws_apigatewayv2_route.transaction_route]
}

# =======================
# 💾 BLOCO 10 — Banco RDS (PostgreSQL)
# =======================
data "aws_vpc" "default" {
  default = true
}

variable "create_rds" {
  type    = bool
  default = true
}

resource "aws_security_group" "finorbit_db_sg" {
  count = var.create_rds ? 1 : 0
  name        = "finorbit-db-sg"
  description = "Permite acesso ao RDS PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # apenas teste
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "finorbit_db" {
  count = var.create_rds ? 1 : 0
  identifier          = "finorbit-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "finorbit_admin"
  password            = "Finorbit123!"
  db_name             = "finorbit"
  publicly_accessible = true
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.finorbit_db_sg[0].id]

  tags = {
    Name = "finorbit-db"
    keep = "true"
  }
}

# =======================
# 🌟 BLOCO 11 — Observabilidade / Visibilidade
# =======================

# 🔔 SNS Topic para alertas
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

# =======================
# 📊 Métricas customizadas via CloudWatch Metric Filters
# =======================

# Lambda Errors - Producer
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
  dimensions = {
    FunctionName = aws_lambda_function.producer.function_name
  }
}

# Lambda Errors - Consumer Deposit
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
  dimensions = {
    FunctionName = aws_lambda_function.consumer_deposit.function_name
  }
}

# Lambda Errors - Consumer Withdraw
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
  dimensions = {
    FunctionName = aws_lambda_function.consumer_withdraw.function_name
  }
}

# SQS ApproximateNumberOfMessagesVisible - Deposit Queue
resource "aws_cloudwatch_metric_alarm" "deposit_queue_length" {
  alarm_name          = "${local.name_prefix}-deposit-queue-length"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 5 # Ajuste conforme sua necessidade
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    QueueName = aws_sqs_queue.transactions_deposit_queue.name
  }
}

# SQS ApproximateNumberOfMessagesVisible - Withdraw Queue
resource "aws_cloudwatch_metric_alarm" "withdraw_queue_length" {
  alarm_name          = "${local.name_prefix}-withdraw-queue-length"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    QueueName = aws_sqs_queue.transactions_withdraw_queue.name
  }
}

# RDS CPU Utilization
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "${local.name_prefix}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.finorbit_db[0].id
  }
}

# =======================
# 📈 Dashboard CloudWatch
# =======================
resource "aws_cloudwatch_dashboard" "finorbit_dashboard" {
  dashboard_name = "finorbit-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0, y = 0, width = 12, height = 6,
        properties = {
          metrics = [["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.producer.function_name]]
          title = "Producer Lambda Errors"
        }
      },
      {
        type = "metric",
        x = 0, y = 7, width = 12, height = 6,
        properties = {
          metrics = [["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.consumer_deposit.function_name]]
          title = "Consumer Deposit Lambda Errors"
        }
      },
      {
        type = "metric",
        x = 0, y = 14, width = 12, height = 6,
        properties = {
          metrics = [["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.consumer_withdraw.function_name]]
          title = "Consumer Withdraw Lambda Errors"
        }
      },
      {
        type = "metric",
        x = 13, y = 0, width = 12, height = 6,
        properties = {
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.transactions_deposit_queue.name]]
          title = "Deposit Queue Length"
        }
      },
      {
        type = "metric",
        x = 13, y = 7, width = 12, height = 6,
        properties = {
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.transactions_withdraw_queue.name]]
          title = "Withdraw Queue Length"
        }
      },
      {
        type = "metric",
        x = 13, y = 14, width = 12, height = 6,
        properties = {
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.finorbit_db[0].id]]
          title = "RDS CPU Utilization"
        }
      }
    ]
  })
}

# =======================
# 📤 OUTPUTS
# =======================
output "api_url" {
  value = "${aws_apigatewayv2_stage.prod.invoke_url}/transaction"
}

output "db_endpoint" {
  value = aws_db_instance.finorbit_db[0].address
}

output "deposit_queue_url" {
  value = aws_sqs_queue.transactions_deposit_queue.url
}

output "withdraw_queue_url" {
  value = aws_sqs_queue.transactions_withdraw_queue.url
}

output "alerts_sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.env}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.finorbit_dashboard.dashboard_name}"
}
