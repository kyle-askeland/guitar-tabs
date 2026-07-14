terraform {
  required_version = ">= 1.10"

  # Bootstrap (once, by hand): aws s3 mb s3://guitar-tabs-tfstate
  backend "s3" {
    bucket       = "guitar-tabs-tfstate"
    key          = "guitar-tabs.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Every taggable resource in the stack inherits these, so this project's spend
# can be isolated in Cost Explorer by the `Project` tag — the account hosts
# other projects, so account-wide totals say nothing useful. The handful of
# resources AWS won't let you tag (IAM role policy, Lambda permission, S3
# bucket policy / public access block, API Gateway routes and integration,
# the CloudFront OAC) are free anyway, so nothing billable goes untagged.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}
