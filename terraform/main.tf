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
# We want to be alarmed if the metric reports a failure (0) at anypoint.
# We are only evaluating the metric every hour because backups will be done
# at most once a day.
resource "aws_cloudwatch_metric_alarm" "media_backup_failure_alarm" {
  alarm_name            = "Media backup failure detected."
  comparison_operator   = "LessThanThreshold"
  evaluation_periods    = 1
  metric_name           = "BackupSuccess"
  namespace             = "PersonalBackup"
  period                = 604800  # 7 days in seconds (60 * 60 * 24 * 7)
  statistic             = "Maximum"
  threshold             = 1
  treat_missing_data    = "breaching"  # Triggers alarm when no data is received
  alarm_description     = "This alarm triggers if the backup success metric is not published at least once every 7 days or if published with value 0."
  alarm_actions         = [aws_sns_topic.backup_alerts.arn]
  insufficient_data_actions = []  # No actions for insufficient data since we're treating missing data as breaching
}

resource "aws_sns_topic" "backup_alerts" {
  name = "backup-failure-alerts"
}

resource "aws_sns_topic_subscription" "sms_alert" {
  topic_arn = aws_sns_topic.backup_alerts.arn
  protocol  = "sms"
  endpoint  = "+1234567890" # Replace with your phone number in E.164 format
}