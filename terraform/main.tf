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

# Failed/aborted multipart uploads leave billable parts behind. The script can
# abort them, but a crashed host cannot, so expire leftovers automatically.
# Database dumps are small and need to be restorable quickly, so they expire
# after a fixed retention instead of being kept forever in Deep Archive.
resource "aws_s3_bucket_lifecycle_configuration" "photo_video_backup_bucket_lifecycle" {
  bucket = aws_s3_bucket.photo_video_backup_bucket.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-database-dumps"
    status = "Enabled"

    filter {
      prefix = var.db_backup_key_prefix
    }

    expiration {
      days = var.db_backup_retention_days
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
        Sid    = "ListBackupBucket",
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation"
        ],
        Resource = [aws_s3_bucket.photo_video_backup_bucket.arn]
      },
      {
        Sid    = "AccessObjectsInBackupBucket",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ],
        Resource = ["${aws_s3_bucket.photo_video_backup_bucket.arn}/*"]
      },
      {
        Sid    = "AccessToPublishCloudwatchMetric",
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
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
#
# A 7-day period would line up with the schedule only by coincidence: one
# missed run shifts the phase, leaves a period with no datapoints, and causes
# alternating false alarms. Instead, evaluate one day at a time and require
# eight consecutive breaching days. The 7 quiet days between weekly runs stay
# below the threshold; a failed run (0) or an eighth day with no data trips it.
resource "aws_cloudwatch_metric_alarm" "media_backup_failure_alarm" {
  alarm_name          = "Media backup failure detected."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 8
  datapoints_to_alarm = 8
  metric_name         = "BackupSuccess"
  namespace           = "MediaBackup" # Must match --namespace in daily-photo-video-backup-s3.sh
  period              = 86400         # 1 day
  statistic           = "Minimum"
  threshold           = 1
  unit                = "Count"
  treat_missing_data  = "breaching" # A missing run is a failure
  alarm_description   = "This alarm triggers if a backup reports failure (0) or if no success metric is published for 8 days."
  alarm_actions       = [aws_sns_topic.backup_alerts.arn]
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
