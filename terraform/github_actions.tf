# ---------- Let GitHub Actions deploy without stored AWS keys ----------
# GitHub proves which repo and branch a workflow runs from with a short-lived
# OIDC token. AWS trades that token for temporary credentials, so no access
# keys are ever saved in GitHub.

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as owner/name."
  type        = string
  default     = "jordannLai/aws-job-market-tracker"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# ---------- Deploy role: only pushes to main can use it ----------

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "jobtracker-github-deploy"
  description          = "Assumed by GitHub Actions on pushes to main to run terraform apply."
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_trust.json
  max_session_duration = 3600
}

# Terraform manages IAM roles, Lambda, S3, CloudFront, and more, so the deploy
# role needs broad permissions. The trust policy above is what limits it:
# only workflows running on the main branch of this one repo can assume it.
resource "aws_iam_role_policy_attachment" "github_deploy" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------- Plan role: pull requests get read-only access ----------

data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = "jobtracker-github-plan"
  description          = "Assumed by GitHub Actions on pull requests to run terraform plan (read-only)."
  assume_role_policy   = data.aws_iam_policy_document.github_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# terraform plan takes a lock by writing a small .tflock file next to the state.
data "aws_iam_policy_document" "github_plan_lock" {
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::jobtracker-jordanlai-tfstate/jobtracker/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "github_plan_lock" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.github_plan_lock.json
}

output "github_deploy_role_arn" {
  description = "Save as the AWS_DEPLOY_ROLE_ARN secret in GitHub."
  value       = aws_iam_role.github_deploy.arn
}

output "github_plan_role_arn" {
  description = "Save as the AWS_PLAN_ROLE_ARN secret in GitHub."
  value       = aws_iam_role.github_plan.arn
}
