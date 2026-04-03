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
  region = "us-east-1" # Change to your preferred primary region
}

# Aliased provider strictly for WAF (CloudFront requirement)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}