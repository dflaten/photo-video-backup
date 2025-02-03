# Photo Video Backup Scripts and Process

TODO: Need to update the scripts below as they are just placeholders for now.

Scripts and programs to automate the backup of my personal photos and videos. I'm ussing [immich](https://immich.app/)
for managing photos but want a backup on the cloud in case of local hardware failures. S3 Glacier - Deep Archive is
the service I'm using for this.

The plan is to run the `daily-photo-video-backup.sh` with a cron job like so:

```bash
# Run backup at 2 AM
0 2 * * * /path/to/daily-photo-video-backup.sh
```

Before that the cloudwatch alarm and sns topic/subscription need to be created along with a role to execute the script
with proper permissions.

## Creating SNS and Cloudwatch Resources
### Create SNS Topic
aws sns create-topic --name media-backup-alerts --region your-aws-region

### Subscribe your phone number to the SNS topic (replace with your phone number)
aws sns subscribe \
    --topic-arn arn:aws:sns:your-aws-region:your-account-id:media-backup-alerts \
    --protocol sms \
    --notification-endpoint "+1234567890"

### Create CloudWatch Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name MediaBackupMissing \
    --alarm-description "Alert when media backup hasn't run in 24 hours" \
    --metric-name BackupSuccess \
    --namespace MediaBackup \
    --statistic Sum \
    --period 86400 \
    --threshold 0 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions arn:aws:sns:your-aws-region:your-account-id:media-backup-alerts \
    --region your-aws-region \
    --treat-missing-data breaching

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
