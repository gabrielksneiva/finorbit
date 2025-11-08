# =======================
# 🔧 BLOCO 1 — Provider AWS
# =======================
provider "aws" {
  region = "us-east-1" # Região Free Tier-friendly
}

# =======================
# 🪧 BLOCO 2 — SNS Topic
# =======================
resource "aws_sns_topic" "transactions" {
  name = "finorbit-transactions"
}

# =======================
# 📬 BLOCO 3 — SQS Queue
# =======================
resource "aws_sqs_queue" "transactions_queue" {
  name = "finorbit-transactions-queue"
}

# =======================
# 🔗 BLOCO 4 — SNS → SQS Subscription
# =======================
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.transactions.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.transactions_queue.arn
}

# Permitir que o SNS publique na fila SQS
resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.transactions_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "SQS:SendMessage"
        Resource  = aws_sqs_queue.transactions_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.transactions.arn
          }
        }
      }
    ]
  })
}

# =======================
# 🧠 BLOCO 5 — IAM Role para Lambda
# =======================
resource "aws_iam_role" "lambda_role" {
  name = "finorbit-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Permissões para Lambda acessar SQS e logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

# Permissão para Lambda puxar imagens do ECR
resource "aws_iam_role_policy_attachment" "lambda_ecr_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Permissão para Lambda publicar no SNS de transações
resource "aws_sns_topic_policy" "allow_lambda_publish" {
  arn = aws_sns_topic.transactions.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowLambdaPublish",
        Effect = "Allow",
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        },
        Action   = "sns:Publish",
        Resource = aws_sns_topic.transactions.arn
      }
    ]
  })
}


# =======================
# 📦 BLOCO — ECR Repositories
# =======================
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "consumer_repo" {
  name = "finorbit-consumer"
}

resource "aws_ecr_repository" "producer_repo" {
  name = "finorbit-producer"
}

# Política que permite que a Lambda puxe as imagens
resource "aws_ecr_repository_policy" "allow_lambda_pull_consumer" {
  repository = aws_ecr_repository.consumer_repo.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowLambdaPull",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "allow_lambda_pull_producer" {
  repository = aws_ecr_repository.producer_repo.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowLambdaPull",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
      }
    ]
  })
}

# =======================
# 🧩 BLOCO 6 — Lambda Function (Consumer)
# =======================

# 🔍 Data source para obter o digest da imagem mais recente do ECR
data "aws_ecr_image" "consumer_latest" {
  repository_name = aws_ecr_repository.consumer_repo.name
  image_tag       = "latest"
}

resource "aws_lambda_function" "consumer" {
  function_name = "finorbit-consumer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"

  # 🧠 Usa o digest da imagem mais recente
  image_uri = "${aws_ecr_repository.consumer_repo.repository_url}@${data.aws_ecr_image.consumer_latest.image_digest}"

  timeout = 10

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.transactions_queue.url
      DB_HOST   = aws_db_instance.finorbit_db.address
      DB_USER   = "finorbit_admin"
      DB_PASS   = "Finorbit123!"
      DB_NAME   = "finorbit"
    }
  }

  depends_on = [
    aws_db_instance.finorbit_db
  ]
}

# =======================
# 🔁 BLOCO 7 — Event Source Mapping (SQS → Lambda)
# =======================
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.transactions_queue.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
  enabled          = true
}


# =======================
# 🧩 BLOCO 8 - Lambda Producer
# =======================
data "aws_ecr_image" "producer_latest" {
  repository_name = aws_ecr_repository.producer_repo.name
  image_tag       = "latest"
}

resource "aws_lambda_function" "producer" {
  function_name = "finorbit-producer"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"

  # Usa digest para detectar nova versão automaticamente
  image_uri = "${aws_ecr_repository.producer_repo.repository_url}@${data.aws_ecr_image.producer_latest.image_digest}"

  timeout = 10

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.transactions.arn
    }
  }

  depends_on = [
    aws_ecr_repository.producer_repo
  ]
}


# API Gateway HTTP
resource "aws_apigatewayv2_api" "finorbit_api" {
  name          = "finorbit-api"
  protocol_type = "HTTP"
}

# Integração Lambda → API
resource "aws_apigatewayv2_integration" "finorbit_integration" {
  api_id                 = aws_apigatewayv2_api.finorbit_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

# Rota POST /transaction
resource "aws_apigatewayv2_route" "transaction_route" {
  api_id    = aws_apigatewayv2_api.finorbit_api.id
  route_key = "POST /transaction"
  target    = "integrations/${aws_apigatewayv2_integration.finorbit_integration.id}"
}

# Permissão para API Gateway invocar a Lambda
resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.finorbit_api.execution_arn}/*"
}

resource "aws_iam_role_policy_attachment" "lambda_rds_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

# ===============================
# 💾 BLOCO 10 — RDS (PostgreSQL)
# ===============================

resource "aws_db_instance" "finorbit_db" {
  identifier          = "finorbit-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "finorbit_admin"
  password            = "Finorbit123!"
  db_name             = "finorbit"
  publicly_accessible = true
  skip_final_snapshot = true

  # Opcional: cria um security group pra acesso
  vpc_security_group_ids = [aws_security_group.finorbit_db_sg.id]
}

resource "aws_security_group" "finorbit_db_sg" {
  name        = "finorbit-db-sg"
  description = "Permite acesso ao RDS PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # apenas para teste — depois restringe!
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Recuperar VPC padrão
data "aws_vpc" "default" {
  default = true
}



# =======================
# 🚀 BLOCO 9 — Deployment manual (força o publish)
# =======================
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.finorbit_api.id
  name        = "prod"
  auto_deploy = true

  depends_on = [
    aws_apigatewayv2_route.transaction_route
  ]
}



# =======================
# 📤 OUTPUTS
# =======================


output "api_url" {
  value = "${aws_apigatewayv2_stage.prod.invoke_url}/transaction"
}

output "api_gateway_id" {
  value = aws_apigatewayv2_api.finorbit_api.id
}
