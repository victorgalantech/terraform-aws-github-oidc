# ================================================
# DynamoDB Table for Terraform State Locking
# ================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(
    var.default_resource_tags,
    {
      Name          = "terraform-state-locks-${var.environment}"
      resource-type = "state-backend"
    }
  )
}
