output "bucket_name" {
  description = "S3 bucket used for the backup"
  value       = aws_s3_bucket.photo_video_backup_bucket.id
}

output "alarm_arn" {
  description = "CloudWatch alarm that fires on backup failure or missing data"
  value       = aws_cloudwatch_metric_alarm.media_backup_failure_alarm.arn
}

output "sns_topic_arn" {
  description = "SNS topic used for backup alerts"
  value       = aws_sns_topic.backup_alerts.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name, or null when disabled"
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.media_backup[0].dashboard_name : null
}
