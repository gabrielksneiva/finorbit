output "sns_topic_arn" {
  value = aws_sns_topic.transactions.arn
}

output "withdraw_queue_url" {
  value = aws_sqs_queue.withdraw_queue.id
}

output "deposit_queue_url" {
  value = aws_sqs_queue.deposit_queue.id
}

output "consumer_withdraw_name" {
  value = aws_lambda_function.consumer_withdraw.function_name
}

output "consumer_deposit_name" {
  value = aws_lambda_function.consumer_deposit.function_name
}
