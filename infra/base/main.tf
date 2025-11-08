locals {
  name_prefix = "finorbit-${var.env}"
}

variable "lambda_role_arn" {}
variable "repositories" {}
variable "queues" {}
variable "producer_image_tag" {}
variable "consumer_image_tag" {}

# =======================
# 🧩 Lambdas
# =======================
resource "aws_lambda_function" "producer" {
  function_name   = "${local.name_prefix}-producer"
  role            = var.lambda_role_arn
  package_type    = "Image"
  image_uri       = "${var.repositories.producer}:${var.producer_image_tag}"
  source_code_hash = base64sha256(var.producer_image_tag)
}

resource "aws_lambda_function" "consumer_deposit" {
  function_name   = "${local.name_prefix}-consumer-deposit"
  role            = var.lambda_role_arn
  package_type    = "Image"
  image_uri       = "${var.repositories.consumer}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)
}

resource "aws_lambda_function" "consumer_withdraw" {
  function_name   = "${local.name_prefix}-consumer-withdraw"
  role            = var.lambda_role_arn
  package_type    = "Image"
  image_uri       = "${var.repositories.consumer}:${var.consumer_image_tag}"
  source_code_hash = base64sha256(var.consumer_image_tag)
}

# Triggers
resource "aws_lambda_event_source_mapping" "deposit_trigger" {
  event_source_arn = var.queues.deposit
  function_name    = aws_lambda_function.consumer_deposit.arn
  batch_size       = 1
  enabled          = true
}

resource "aws_lambda_event_source_mapping" "withdraw_trigger" {
  event_source_arn = var.queues.withdraw
  function_name    = aws_lambda_function.consumer_withdraw.arn
  batch_size       = 1
  enabled          = true
}
