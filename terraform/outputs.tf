output "lambda_functions" {
  description = "Pipeline Lambda functions."
  value       = { for k, fn in aws_lambda_function.this : k => fn.function_name }
}

output "alerts_topic_arn" {
  description = "SNS topic that receives failure alerts."
  value       = aws_sns_topic.alerts.arn
}
