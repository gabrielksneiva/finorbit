##############################################
# 📁 /infra/base/main.tf
# Infraestrutura base: VPC, SG default, RDS, SNS/SQS, ECR
##############################################

locals {
  name_prefix = "finorbit-${var.env}"
}

# =======================
# 🧠 IAM Role
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

resource "aws_iam_role_policy_attachment" "lambda_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])
  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value
}

# =======================
# 📨 SNS & SQS
# =======================
resource "aws_sns_topic" "transactions" {
  name = "${local.name_prefix}-transactions"
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sqs_queue" "transactions_deposit_queue" {
  name = "${local.name_prefix}-deposit-queue"
}

resource "aws_sqs_queue" "transactions_withdraw_queue" {
  name = "${local.name_prefix}-withdraw-queue"
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  for_each = {
    deposit  = aws_sqs_queue.transactions_deposit_queue.arn
    withdraw = aws_sqs_queue.transactions_withdraw_queue.arn
  }

  topic_arn     = aws_sns_topic.transactions.arn
  protocol      = "sqs"
  endpoint      = each.value
  filter_policy = jsonencode({ type = [each.key] })
}

resource "aws_sqs_queue_policy" "allow_sns_publish" {
  for_each = {
    deposit  = aws_sqs_queue.transactions_deposit_queue
    withdraw = aws_sqs_queue.transactions_withdraw_queue
  }

  queue_url = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "SQS:SendMessage"
      Resource  = each.value.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.transactions.arn } }
    }]
  })
}

# =======================
# 📦 ECR
# =======================
resource "aws_ecr_repository" "consumer_repo" {
  name         = "${local.name_prefix}-consumer"
  force_delete = true
}

resource "aws_ecr_repository" "producer_repo" {
  name         = "${local.name_prefix}-producer"
  force_delete = true
}

resource "aws_ecr_repository_policy" "lambda_access" {
  for_each = {
    consumer = aws_ecr_repository.consumer_repo.name
    producer = aws_ecr_repository.producer_repo.name
  }
  repository = each.value
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowLambdaPull"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    }]
  })
}

# =======================
# 💾 Banco de Dados (RDS)
# =======================

# Obtém a VPC e o Security Group default
data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "default" {
  filter {
    name   = "group-name"
    values = ["default"]
  }
  vpc_id = data.aws_vpc.default.id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_instance" "finorbit_db" {
  count                   = var.create_rds ? 1 : 0
  identifier              = "${local.name_prefix}-db"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "finorbit_admin"
  password                = "Finorbit123!"
  db_name                 = "finorbit"
  publicly_accessible     = true
  skip_final_snapshot     = true
  vpc_security_group_ids  = [data.aws_security_group.default.id]
}
