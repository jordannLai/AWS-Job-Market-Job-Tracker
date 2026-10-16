data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # The Adzuna keys stay in Parameter Store and are never read by Terraform,
  # so the secret values never end up in the Terraform state file.
  ssm_parameter_arn = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/jobtracker/*"

  # One entry per pipeline stage. Everything else (functions, roles,
  # schedules, alarms, log groups) is generated from this map.
  lambdas = {
    fetch = {
      description = "Pulls new job postings from the Adzuna API into the raw zone."
      timeout     = 180 # retries with backoff can add waiting time
      schedule    = "cron(0 8 * * ? *)"
      environment = {
        BUCKET_NAME = var.data_bucket_name
      }
    }
    transform = {
      description = "Flattens raw postings and tags skills into the processed zone."
      timeout     = 60
      schedule    = "cron(15 8 * * ? *)"
      environment = {
        BUCKET_NAME = var.data_bucket_name
      }
    }
    publish = {
      description = "Computes the dashboard numbers and writes summary.json to the site bucket."
      timeout     = 60
      schedule    = "cron(30 8 * * ? *)"
      environment = {
        DATA_BUCKET = var.data_bucket_name
        SITE_BUCKET = var.site_bucket_name
      }
    }
  }
}
