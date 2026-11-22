variable "my_account_id" {
  description = "AWS Account ID that is allowed to access the S3 bucket"
  type        = string
}

variable "my_unique_uid" {
  description = "Unique identifier which will be used to create name for role and bucket"
  type        = string
}

variable "alert_email" {
  description = "Email address for backup alerts. SNS email delivery is free for the first 1,000 messages/month. Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "alert_phone_number" {
  description = "Phone number in E.164 format for SMS backup alerts. SMS has no free tier (~$0.00645/message in the US plus carrier fees). Leave empty to skip the subscription."
  type        = string
  default     = ""
}

variable "enable_dashboard" {
  description = "Create the CloudWatch dashboard. Dashboards are free for the first 3 per account, then $3/month."
  type        = bool
  default     = true
}
