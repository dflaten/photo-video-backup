# Photo Video Backup Scripts and Process

TODO: Find a notification method for backup job failures. Then run my first backup.

Scripts and programs to automate the backup of my personal photos and videos. I'm ussing [immich](https://immich.app/)
for managing photos but want a backup on the cloud in case of local hardware failures. I have evaluated two options to do this.

I first looked at S3 Glacier as I am familiar with the service and the prices seem resonable. However when looking at what it
would cost to retrieve all the photos in the future if I needed to restore a backup I realized the costs could get excessive.

I have about 1 TB of photos/videos right now and would expect this to increase. Storage costs for S3 would be about $2 a month
but retrieval costs on that 1 TB would be ~100$. See [pricing info here](https://aws.amazon.com/s3/pricing/).

Backblaze will cost 6 dollars per TB per month and I will be able to store whatever I need there.


## Backblaze b2 backup

Will create a cron job that runs:

`rclone copy /immich/directory b2remote:name-of-bucket/immich --progress`

Once a week to update the backup. Will also see if I can set something up to text me if this doesn't work for some reason.

## S3 Glacier - How I could use S3 in the future if I decide..

The plan is to run the `daily-photo-video-backup-s3.sh` with a cron job like so:

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
