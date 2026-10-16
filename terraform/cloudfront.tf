# ---------- Dashboard hosting: private S3 bucket behind CloudFront ----------
# Imported from the console setup (see cloudfront_import.tf), then cleaned up
# from Terraform's generated config.

# AWS's managed "CachingOptimized" policy: honors each file's Cache-Control
# header (summary.json: 1 hour, index.html: 5 minutes).
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Lets CloudFront sign its requests to the private site bucket.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "oac-jobtracker-jordanlai-site.s3.us-east-2.amazonaws-mvbb9xxch67"
  description                       = "Created by CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  site_origin_id = "jobtracker-jordanlai-site.s3.us-east-2.amazonaws.com-mvbb6mwwob5"
}

resource "aws_cloudfront_distribution" "dashboard" {
  enabled             = true
  default_root_object = "index.html"
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"

  tags = {
    Name = "jobtracker-dashboard"
  }

  origin {
    origin_id                   = local.site_origin_id
    domain_name                 = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id    = aws_cloudfront_origin_access_control.site.id
    connection_attempts         = 3
    connection_timeout          = 10
    response_completion_timeout = 0
  }

  default_cache_behavior {
    target_origin_id       = local.site_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true

    grpc_config {
      enabled = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  # Recreating the distribution would change the dashboard's URL.
  lifecycle {
    prevent_destroy = true
  }
}

# Only this CloudFront distribution may read the site bucket.
data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.dashboard.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
}

# The dashboard page itself. Editing dashboard/index.html and running
# terraform apply deploys the new version. summary.json is written daily by
# the publish Lambda and is not managed here.
resource "aws_s3_object" "index" {
  bucket        = aws_s3_bucket.site.id
  key           = "index.html"
  source        = "${path.module}/../dashboard/index.html"
  etag          = filemd5("${path.module}/../dashboard/index.html")
  content_type  = "text/html; charset=utf-8"
  cache_control = "max-age=300"
}
