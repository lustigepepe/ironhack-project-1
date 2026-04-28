terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-hagen-2026" # ← Change this
    key            = "my-app/dev/terraform.tfstate"      # Path inside bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock-pr1-hagen" # For locking
    encrypt        = true
  }
}
