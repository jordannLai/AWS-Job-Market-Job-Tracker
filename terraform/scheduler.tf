# Runs fetch (8:00), transform (8:15), and publish (8:30) every morning.
resource "aws_scheduler_schedule" "daily" {
  for_each = local.lambdas

  name                         = "jobtracker-daily-${each.key}"
  group_name                   = "default"
  description                  = "Runs jobtracker-${each.key} every morning."
  schedule_expression          = each.value.schedule
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this[each.key].arn
    role_arn = aws_iam_role.scheduler.arn
  }
}
