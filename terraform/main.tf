provider "aws" {
  region = "us-east-1"
}

# S3 bucket for photo/video backup
resource "aws_s3_bucket" "photo_video_backup_bucket" {
  bucket = "dflaten-photo-video-backup"

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
        Sid    = "AllowSpecificAccount"
        Effect = "Allow"
        Principal = {
          AWS = ["arn:aws:iam::${var.my_account_id}:user/DevAdminAccess",
          aws_iam_user.photo_video_server_user.arn]
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
      },
      {
        Sid       = "DenyAllOthers"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.photo_video_backup_bucket.arn,
          "${aws_s3_bucket.photo_video_backup_bucket.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" : "${var.my_account_id}"
          }
        }
      }
    ]
  })
}

# Create IAM user for your Linux machine
resource "aws_iam_user" "photo_video_server_user" {
  name = "dflaten-photo-video-server"
}

# Create policy for S3 bucket access
resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3-photo-video-backup-bucket-access-policy"
  description = "Policy to allow access to S3 bucket for storing backup of video and photos."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
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
      }
    ]
  })
}
