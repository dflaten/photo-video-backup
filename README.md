# Photo Video Backup Scripts and Process

Scripts and programs to automate the backup of my personal photos and videos. I'm using [immich](https://immich.app/) for image storage and
backing up a copy to the cloud for long term storage. I've outlined how to do so with two possible options below, S3 and Backblaze.



## S3 Glacier

Run the `daily-photo-video-backup-s3.sh` with a cron job like so:

```bash
# Run backup at 2 AM
0 2 * * * /path/to/daily-photo-video-backup.sh
```

Before that the cloudwatch alarm and sns topic/subscription need to be created along with a role to execute the script
with proper permissions.

## Creating SNS and Cloudwatch Resources
### Create SNS Topic
```bash
aws sns create-topic --name media-backup-alerts --region your-aws-region
```

### Subscribe your phone number to the SNS topic (replace with your phone number)
```bash
aws sns subscribe \
    --topic-arn arn:aws:sns:your-aws-region:your-account-id:media-backup-alerts \
    --protocol sms \
    --notification-endpoint "+1234567890"
```

### Create CloudWatch Alarm
```bash
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
4. Select Backblaze B2 from the list of options and follow the prompts to add the app key, make sure your id is the one listed with your keythe one listed with your key.
5. Set `export RCLONE_FAST_LIST=true` on your cli to use the cheaper commands.

Will create a cron job that runs:

`rclone copy /immich/directory b2remote:name-of-bucket/immich --progress`

Once a week to update the backup. Will also see if I can set something up to text me if this doesn't work for some reason.
