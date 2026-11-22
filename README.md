# Photo Video Backup Scripts and Process

Scripts and programs to automate the backup of personal photos and videos. This assumes [immich](https://immich.app/) on a linux machine is being used for image storage and
a backup copy to the cloud is needed for extra redundancy.

It has been tested with ~21,000 photos and 1,900 videos.

## Backup Process
[rclone](https://rclone.org/) is used coordinated with a bash script in this repo to preform the backup for photos/videos and the database from immich to S3.

The aws cli is useful for verification on the machine running immich, you can install with snap by using:
`snap install aws-cli --classic`

AWS access is needed through a role or access key. Access key is not recommended in general but for personal use it is probably fine. Create an access key for the immich machine to use for the backup to S3 with this command:

`aws iam create-access-key --user-name [YOUR-IDENTIFIER]-photo-video-server`

Before running the `daily-photo-video-backup-s3.sh` script rclone must be configured. 

`rclone config`

During configuration, provide:

    Storage provider: Choose "Amazon S3 Compliant Storage Providers"
    AWS Access Key ID: Your AWS access key
    AWS Secret Access Key: Your AWS secret key
    Region: Your S3 bucket's region (e.g., us-east-1, eu-west-1)
    Remote name: s3

The script uses the remote name `s3` in `BUCKET_PATH` (for example `s3:my-bucket/backup`). If you name the remote something else, update `BUCKET_PATH` to match.

Then copy the example config and edit the values:

```bash
cp config.example.txt config.txt
```

`config.txt` is ignored by git, so your local paths and bucket name are not committed.

`LOG_DIRECTORY` may be absolute or relative. Relative paths are resolved against the script's directory, so manual runs and cron runs log to the same place.

## Weekly Cron Setup
To run the backup automatically once per week, first make sure the script is executable:

```bash
chmod +x /home/david/projects/photo-video-backup/daily-photo-video-backup-s3.sh
```

Open your crontab:

```bash
crontab -e
```

Add an entry like this to run the backup every Sunday at 2:00 AM:

```cron
0 2 * * 0 /home/david/projects/photo-video-backup/daily-photo-video-backup-s3.sh
```

If your environment does not load the expected `PATH` in cron, use the full paths for dependencies such as `rclone` and `aws`, or define `PATH` at the top of the crontab.

After saving, verify the entry was installed:

```bash
crontab -l
```

It is also worth running the script manually once before relying on cron so any `rclone`, AWS, or config issues can be fixed interactively.

## Alerting
The script publishes a `BackupSuccess` metric to the `MediaBackup` CloudWatch namespace: `1` on success and `0` on failure. The Terraform in `terraform/` creates an alarm that stays in `ALARM` if:

* any run in the last 7 days reported `0`, or
* no metric was published in the last 7 days (`treat_missing_data = "breaching"`).

Set notification targets in `terraform.tfvars`:

```terraform
alert_email        = "you@example.com"
# alert_phone_number = "+15551234567"
```

* Email is the cheapest path: the first 1,000 SNS email deliveries per month are free. AWS sends a one-time confirmation link that must be clicked.
* SMS is opt-in because it has no free tier (~$0.00645 per US message plus carrier fees).

The alarm's namespace must match the script's namespace (`MediaBackup`). If you change one, change the other, or the alarm will sit in `ALARM` forever because it never receives data.

After applying Terraform, the alarm may remain in `ALARM` until the next successful run publishes `1`. Run the script manually to clear it.

## CloudWatch Dashboard
Terraform creates a `media-backup` dashboard with the alarm status, backup success history, S3 bucket size and object count, SNS deliveries, and estimated AWS charges. Set `enable_dashboard = false` in `terraform.tfvars` if you do not want it.

Costs: dashboards are free for the first three per account and $3/month after that. The S3 graphs use only the free daily storage metrics; S3 request metrics are deliberately not used because CloudWatch bills those as custom metrics.

## Costs
The setup is designed to stay cheap:

| Item | Cost |
| --- | --- |
| S3 Glacier Deep Archive storage | $0.00099/GB-month (~$1.01/TB) |
| PUT requests to Deep Archive | $0.05 per 1,000 (initial upload of ~20k files is about $1) |
| LIST requests | $0.005 per 1,000 requests (a weekly run is a few hundred requests, well under $0.01) |
| CloudWatch custom metric | $0.30/month (first 10 free) |
| CloudWatch alarm | $0.10/month (first 10 standard alarms free) |
| CloudWatch dashboard | Free for the first 3, then $3/month |
| SNS email | Free for the first 1,000/month |
| SNS SMS | ~$0.00645/message in the US plus carrier fees |

Deep Archive has a **180-day minimum storage duration**. Deleting an object earlier is still billed for the remainder of the 180 days. Because the script uses `rclone sync`, objects removed from the source are deleted from S3 too; the script limits this with `--max-delete 100` and refuses to run if the source directory is missing or empty. If you would rather keep a permanent archive and avoid early-deletion charges entirely, use `rclone copy` instead of `rclone sync`.

Restoring is a separate cost: $0.02/GB for a standard restore (up to 12 hours) or $0.0025/GB for bulk (up to 48 hours), plus request and egress charges ($0.09/GB after the first 100 GB/month).

## Terraform Included
The terraform included here includes the AWS infra needed as a part of the backup process to S3 including:

* A S3 Bucket with public access blocked
* SSE-S3 encryption for the bucket
* IAM Policy for the bucket
* IAM User for my linux machine to connect to the bucket for backup
* CloudWatch metric alarm and SNS topic for failure notifications
* CloudWatch dashboard for backup and bucket stats

Confidential information like the AWS account is kept in a `terraform.tfvars` file which is in the form:

```terraform
my_account_id = "123456789012"
my_unique_uid = "example"
alert_email   = "you@example.com"
```

*In OtherBackupMethods.md two other alternative options for backup are provided, pure S3 and Backblaze.*
