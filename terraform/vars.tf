variable "my_account_id" {
  description = "AWS Account ID that is allowed to access the S3 bucket"
  type        = string
}

variable "my_unique_uid" {
  description = "Unique identifier which will be used to create name for role and bucket"
  type = string
}
