output "lambda_functions" {
  description = "Pipeline Lambda functions."
  value       = { for k, fn in aws_lambda_function.this : k => fn.function_name }
}

output "dashboard_url" {
  description = "Public URL of the dashboard."
  value       = "https://${aws_cloudfront_distribution.dashboard.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "Used to clear CloudFront's cache after a deploy."
  value       = aws_cloudfront_distribution.dashboard.id
}

output "alerts_topic_arn" {
  description = "SNS topic that receives failure alerts."
  value       = aws_sns_topic.alerts.arn
}
