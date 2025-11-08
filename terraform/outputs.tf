output "sns_topic_arn" {
  value = aws_sns_topic.transactions.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.transactions_queue.id
}

output "lambda_name" {
  value = aws_lambda_function.consumer.function_name
}
