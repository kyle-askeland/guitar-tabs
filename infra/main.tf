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

provider "aws" {
  region = var.region
}
