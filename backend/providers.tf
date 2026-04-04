terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider for your main region
provider "aws" {
  region = var.aws_region
}

# Aliased provider strictly for WAF (CloudFront requirement)
provider "aws" {
  alias  = "ap-southeast-1"
  region = "ap-southeast-1"
}