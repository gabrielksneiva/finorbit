# IAM Role usado pelas Lambdas
output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

# ECRs
output "ecr_consumer_repo_url" {
  value = aws_ecr_repository.consumer_repo.repository_url
}

output "ecr_producer_repo_url" {
  value = aws_ecr_repository.producer_repo.repository_url
}

# SQS Queues
output "sqs_deposit_arn" {
  value = aws_sqs_queue.transactions_deposit_queue.arn
}

output "sqs_withdraw_arn" {
  value = aws_sqs_queue.transactions_withdraw_queue.arn
}

# SNS Topic
output "sns_topic_arn" {
  value       = aws_sns_topic.transactions.arn
  description = "ARN do tópico SNS de transações"
}