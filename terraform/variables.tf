variable "region" {
  description = "AWS region for every resource in this project."
  type        = string
  default     = "us-east-2"
}

variable "data_bucket_name" {
  description = "S3 bucket holding raw and processed job postings."
  type        = string
  default     = "jobtracker-jordanlai-data"
}

variable "site_bucket_name" {
  description = "S3 bucket holding the dashboard (served through CloudFront)."
  type        = string
  default     = "jobtracker-jordanlai-site"
}

variable "alert_email" {
  description = "Email address that receives pipeline failure alerts. Set it in terraform.tfvars (not committed)."
  type        = string
}

variable "lambda_runtime" {
  description = "Python runtime for all Lambda functions."
  type        = string
  default     = "python3.14"
}

variable "schedule_timezone" {
  description = "Time zone the daily schedules run in."
  type        = string
  default     = "America/New_York"
}
