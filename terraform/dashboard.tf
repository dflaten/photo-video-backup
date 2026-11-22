data "aws_region" "current" {}

# Cost note: this dashboard uses only free S3 daily storage metrics and SNS
# service metrics. S3 request metrics are deliberately not used because
# CloudWatch bills them as custom metrics. Dashboards are free for the first
# three per account, then $3/month.
resource "aws_cloudwatch_dashboard" "media_backup" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "media-backup"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "alarm"
        x      = 0
        y      = 0
        width  = 24
        height = 3
        properties = {
          title  = "Backup alarm: ${aws_cloudwatch_metric_alarm.media_backup_failure_alarm.alarm_name}"
          alarms = [aws_cloudwatch_metric_alarm.media_backup_failure_alarm.arn]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 3
        width  = 8
        height = 6
        properties = {
          title   = "Backup success (1 = success, 0 = failure)"
          region  = data.aws_region.current.name
          view    = "timeSeries"
          stacked = false
          stat    = "Minimum"
          period  = 86400
          start   = "-P30D"
          metrics = [
            ["MediaBackup", "BackupSuccess", { label = "BackupSuccess", color = "#2ca02c" }]
          ]
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 3
        width  = 8
        height = 6
        properties = {
          title  = "Bucket size by storage class (bytes)"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 86400
          start  = "-P30D"
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.photo_video_backup_bucket.id, "StorageType", "DeepArchiveStorage", { label = "Deep Archive" }],
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.photo_video_backup_bucket.id, "StorageType", "StandardStorage", { label = "Standard" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 3
        width  = 8
        height = 6
        properties = {
          title  = "Object count"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Average"
          period = 86400
          start  = "-P30D"
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.photo_video_backup_bucket.id, "StorageType", "AllStorageTypes", { label = "Objects" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "SNS notifications per day"
          region = data.aws_region.current.name
          view   = "timeSeries"
          stat   = "Sum"
          period = 86400
          start  = "-P30D"
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.backup_alerts.name, { label = "Published" }],
            ["AWS/SNS", "NumberOfNotificationsDelivered", "TopicName", aws_sns_topic.backup_alerts.name, { label = "Delivered" }],
            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", aws_sns_topic.backup_alerts.name, { label = "Failed" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Estimated AWS charges (USD)"
          region = "us-east-1" # Billing metrics exist only in us-east-1
          view   = "timeSeries"
          stat   = "Maximum"
          period = 21600
          start  = "-P30D"
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { label = "Estimated charges" }]
          ]
        }
      },
      {
        type   = "text"
        x      = 0
        y      = 15
        width  = 24
        height = 6
        properties = {
          markdown = <<-EOT
            # Media backup

            - Bucket: `${aws_s3_bucket.photo_video_backup_bucket.id}` (S3 Glacier Deep Archive for media)
            - Media is copied, never deleted. Prune manually (see README).
            - Database dumps: `${aws_s3_bucket.photo_video_backup_bucket.id}/${var.db_backup_key_prefix}` in Standard storage, expired after ${var.db_backup_retention_days} days.
            - Alarm: `${aws_cloudwatch_metric_alarm.media_backup_failure_alarm.alarm_name}` — 7 consecutive breaching days, missing data is breaching
            - S3 storage metrics and SNS metrics shown here are free. S3 request metrics are intentionally not used: CloudWatch bills them as custom metrics.
            - Costs: 1 custom metric (~$0.30/mo) + 1 alarm (~$0.10/mo) + dashboard (free for the first 3, then $3/mo).
            - The billing graph requires "Receive Billing Alerts" to be enabled in the account preferences, and stays empty otherwise.
          EOT
        }
      },
    ]
  })
}
