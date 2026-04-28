terraform {
  required_version = ">= 1.10.0" # You can keep 1.14 if you want

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
