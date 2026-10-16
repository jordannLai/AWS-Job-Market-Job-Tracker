# ---------- Email alerts when the pipeline breaks ----------

resource "aws_sns_topic" "alerts" {
  name = "jobtracker-alerts"
}

# AWS emails a confirmation link after the first apply. Alerts arrive only
# after you click it.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Any failed run of any stage (including a fetch that gave up after retries).
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambdas

  alarm_name        = "jobtracker-${each.key}-errors"
  alarm_description = "jobtracker-${each.key} failed. Check its CloudWatch logs."
  namespace         = "AWS/Lambda"
  metric_name       = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.this[each.key].function_name
  }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# Dead man's switch: fires if the publish step hasn't run at all in a day,
# which catches a deleted or disabled schedule that the error alarms can't.
resource "aws_cloudwatch_metric_alarm" "pipeline_stalled" {
  alarm_name        = "jobtracker-pipeline-stalled"
  alarm_description = "jobtracker-publish has not run in the last 24 hours. Check the EventBridge schedules."
  namespace         = "AWS/Lambda"
  metric_name       = "Invocations"
  dimensions = {
    FunctionName = aws_lambda_function.this["publish"].function_name
  }
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
