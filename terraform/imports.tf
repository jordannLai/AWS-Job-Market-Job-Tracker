# These resources were first created by hand in the AWS console.
# Import blocks bring them under Terraform's control without deleting or
# recreating them, so there is no downtime and no data is lost.
# After the first successful apply they do nothing and can be deleted.

import {
  to = aws_s3_bucket.data
  id = "jobtracker-jordanlai-data"
}

import {
  to = aws_s3_bucket_public_access_block.data
  id = "jobtracker-jordanlai-data"
}

import {
  to = aws_s3_bucket.site
  id = "jobtracker-jordanlai-site"
}

import {
  to = aws_s3_bucket_public_access_block.site
  id = "jobtracker-jordanlai-site"
}

import {
  to = aws_lambda_function.this["fetch"]
  id = "jobtracker-fetch"
}

import {
  to = aws_lambda_function.this["transform"]
  id = "jobtracker-transform"
}

import {
  to = aws_lambda_function.this["publish"]
  id = "jobtracker-publish"
}

import {
  to = aws_cloudwatch_log_group.lambda["fetch"]
  id = "/aws/lambda/jobtracker-fetch"
}

import {
  to = aws_cloudwatch_log_group.lambda["transform"]
  id = "/aws/lambda/jobtracker-transform"
}

import {
  to = aws_cloudwatch_log_group.lambda["publish"]
  id = "/aws/lambda/jobtracker-publish"
}

import {
  to = aws_scheduler_schedule.daily["fetch"]
  id = "default/jobtracker-daily-fetch"
}

import {
  to = aws_scheduler_schedule.daily["transform"]
  id = "default/jobtracker-daily-transform"
}

import {
  to = aws_scheduler_schedule.daily["publish"]
  id = "default/jobtracker-daily-publish"
}
