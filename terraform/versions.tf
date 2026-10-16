terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  # State lives in S3 so it survives your laptop and can be shared with
  # GitHub Actions later. use_lockfile stops two runs from editing it at once.
  # The bucket is created once by hand (see terraform/README.md).
  backend "s3" {
    bucket       = "jobtracker-jordanlai-tfstate"
    key          = "jobtracker/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "aws-job-market-tracker"
      ManagedBy = "terraform"
    }
  }
}
