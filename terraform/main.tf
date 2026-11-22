provider "aws" {
  region = "us-east-1"
}

# S3 bucket for photo/video backup
resource "aws_s3_bucket" "photo_video_backup_bucket" {
  bucket = "${var.my_unique_uid}-photo-video-backup"

  tags = {
    Name = "photo-video-backup"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "photo_video_backup_bucket_encryption" {
  bucket = aws_s3_bucket.photo_video_backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "photo_video_backup_bucket_public_access_block" {
  bucket = aws_s3_bucket.photo_video_backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "photo_video_backup_bucket_policy" {
  bucket = aws_s3_bucket.photo_video_backup_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSpecificUsers"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.my_account_id}:user/DevAdminAccess",
            aws_iam_user.photo_video_server_user.arn
          ]
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.photo_video_backup_bucket.arn,
          "${aws_s3_bucket.photo_video_backup_bucket.arn}/*"
        ]
      }
    ]
  })

}

# Create IAM user for your Linux machine
resource "aws_iam_user" "photo_video_server_user" {
  name = "${var.my_unique_uid}-photo-video-server"
}

# Create policy for S3 bucket access
resource "aws_iam_policy" "s3_user_access_policy" {
  name        = "s3-photo-video-backup-bucket-access-and-alarm-policy"
  description = "Policy to allow access to S3 bucket for storing backup of video and photos."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AccessS3BucketForBackup",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Resource = [
          aws_s3_bucket.photo_video_backup_bucket.arn,
          "${aws_s3_bucket.photo_video_backup_bucket.arn}/*"
        ]
      },
      {
        Sid    = "AccessToPublishCloudwatchMetric",
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      },
      {
        Sid    = "CreateKeyForBackupAccess",
        Effect = "Allow",
        Action = [
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey"
        ],
        Resource = [aws_iam_user.photo_video_server_user.arn]
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "backup_user_policy_attachement" {
  user       = aws_iam_user.photo_video_server_user.name
  policy_arn = aws_iam_policy.s3_user_access_policy.arn
}
# Create alarm for backup metric
# The script publishes 1 on success and 0 on failure, at most once a week.
# Minimum over the 7-day window catches any failure in the window, and
# treat_missing_data = "breaching" catches a run that never happened at all.
resource "aws_cloudwatch_metric_alarm" "media_backup_failure_alarm" {
  alarm_name                = "Media backup failure detected."
  comparison_operator       = "LessThanThreshold"
  evaluation_periods        = 1
  metric_name               = "BackupSuccess"
  namespace                 = "MediaBackup" # Must match --namespace in daily-photo-video-backup-s3.sh
  period                    = 604800        # 7 days in seconds (60 * 60 * 24 * 7)
  statistic                 = "Minimum"
  threshold                 = 1
  unit                      = "Count"
  treat_missing_data        = "breaching" # Triggers alarm when no data is received
  alarm_description         = "This alarm triggers if any backup reports failure (0) or if no success metric is published within 7 days."
  alarm_actions             = [aws_sns_topic.backup_alerts.arn]
  insufficient_data_actions = [] # No actions for insufficient data since we're treating missing data as breaching
}

resource "aws_sns_topic" "backup_alerts" {
  name = "backup-failure-alerts"
}

# Email is the cheapest notification path: the first 1,000 deliveries/month are
# free. The subscription is created only when alert_email is set, and AWS emails
# a confirmation link that must be clicked once.
resource "aws_sns_topic_subscription" "email_alert" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Optional SMS alerts. SMS is charged per message with no free tier, so this is
# opt-in via alert_phone_number.
resource "aws_sns_topic_subscription" "sms_alert" {
  count = var.alert_phone_number == "" ? 0 : 1

  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "sms"
  endpoint  = var.alert_phone_number
}
