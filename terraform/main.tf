provider "aws" {
  region = "us-east-1"
}

# S3 bucket for photo/video backup
resource "aws_s3_bucket" "backup_bucket" {
  bucket = "dflaten-photo-video-backup"

  tags = {
    Name        = "Photo and Video Backup"
    Environment = "Production"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "backup_bucket_encryption" {
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "backup_bucket_versioning" {
  bucket = aws_s3_bucket.backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CloudWatch metric
resource "aws_cloudwatch_metric_alarm" "backup_success_alarm" {
  alarm_name          = "BackupSuccessAlarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackupSuccess"
  namespace           = "MediaBackup"
  period              = 86400 # 24 hours in seconds
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alarm when backup success count is less than 1 per day"

  dimensions = {
    BucketName = aws_s3_bucket.backup_bucket.id
  }

  insufficient_data_actions = []
}
