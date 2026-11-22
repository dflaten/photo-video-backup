# Other Backup Methods

## S3 Glacier

Run the `daily-photo-video-backup-s3.sh` with a cron job like so:

```bash
# Run backup every Sunday at 2 AM
0 2 * * 0 /path/to/daily-photo-video-backup-s3.sh
```

Before that the cloudwatch alarm and sns topic/subscription need to be created along with a role to execute the script
with proper permissions. The Terraform in this repo provisions these resources; the commands below are for setting them
up manually.

## Creating SNS and Cloudwatch Resources
### Create SNS Topic
```bash
aws sns create-topic --name backup-failure-alerts --region your-aws-region
```

### Subscribe your phone number to the SNS topic (replace with your phone number)
```bash
aws sns subscribe \
    --topic-arn arn:aws:sns:your-aws-region:your-account-id:backup-failure-alerts \
    --protocol sms \
    --notification-endpoint "+1234567890"
```

An email subscription is cheaper (free for the first 1,000/month); use `--protocol email` instead.

### Create CloudWatch Alarm
```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "Media backup failure detected." \
    --alarm-description "Alert when any backup reports failure (0) or no success metric is published within 7 days" \
    --metric-name BackupSuccess \
    --namespace MediaBackup \
    --statistic Minimum \
    --period 604800 \
    --threshold 1 \
    --unit Count \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions arn:aws:sns:your-aws-region:your-account-id:backup-failure-alerts \
    --region your-aws-region \
    --treat-missing-data breaching
```

#### Cloudwatch Policy for Role for Script execution
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "cloudwatch:namespace": "MediaBackup"
                }
            }
        }
    ]
}
```

## Backblaze B2 Backup

1. First get an Application Key from Backblaze so you can connect to their buckets.
2. Then install `rclone` on Ubuntu: `sudo snap install rclone`
3. Configure `rclone` with `rclone config` and select a `remote` connection to be created after you give it a name like `b2`.
4. Select Backblaze B2 from the list of options and follow the prompts to add the app key, make sure your id is the one listed with your key.
5. Set `export RCLONE_FAST_LIST=true` on your cli to use the cheaper commands.

Will create a cron job that runs:

`rclone copy /immich/directory b2remote:name-of-bucket/immich --progress`

Once a week to update the backup. Will also see if I can set something up to text me if this doesn't work for some reason.
