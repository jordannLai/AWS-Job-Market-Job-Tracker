# Zip each function's folder (lambda/fetch, lambda/transform, lambda/publish).
data "archive_file" "lambda" {
  for_each    = local.lambdas
  type        = "zip"
  source_dir  = "${path.module}/../lambda/${each.key}"
  output_path = "${path.module}/build/${each.key}.zip"
  excludes    = ["__pycache__", "__pycache__/**"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.lambdas
  name              = "/aws/lambda/jobtracker-${each.key}"
  retention_in_days = 30
}

resource "aws_lambda_function" "this" {
  for_each = local.lambdas

  function_name    = "jobtracker-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = var.lambda_runtime
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256
  timeout          = each.value.timeout
  memory_size      = 128

  environment {
    variables = each.value.environment
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
    aws_iam_role_policy_attachment.lambda_logs,
  ]
}
