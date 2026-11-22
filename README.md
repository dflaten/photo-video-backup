# Photo Video Backup Scripts and Process

Scripts and programs to automate the backup of personal photos and videos. This assumes [immich](https://immich.app/) on a linux machine is being used for image storage and
a backup copy to the cloud is needed for extra redundancy.

It has been tested with ~21,000 photos and 1,900 videos.

## Backup Process
[rclone](https://rclone.org/) is used coordinated with a bash script in this repo to perform the backup of photos/videos and the Immich database to S3.

The media backup uses `rclone copy`, not `rclone sync`: files are added to the archive and **never deleted automatically**. Removing a photo from Immich, or a drive that fails to mount, cannot remove anything from S3. Pruning the archive is a deliberate manual step (see [Pruning](#pruning-the-archive)). Files are compared by size (`--size-only`); an in-place edit that keeps the same byte size will not be re-uploaded, which is a deliberate trade-off for immutable Immich assets.

Immich database dumps (`*.sql.gz`) are copied to a separate `backups/db/` prefix in **Standard** storage, not Deep Archive, so restoring a recent dump takes minutes instead of hours. They expire after 90 days via an S3 lifecycle rule. The run fails if the newest dump is more than 8 days old, so an Immich database backup that silently stops is caught instead of copying nothing.

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

The script uses the remote name `s3` in `BUCKET_PATH` (for example `s3:my-bucket` or `s3:my-bucket/backup`). If you name the remote something else, update `BUCKET_PATH` to match. If you use a sub-path, also set `db_backup_key_prefix` in `terraform.tfvars` so the database-dump lifecycle rule matches.

Then copy the example config and edit the values:

```bash
cp config.example.txt config.txt
```

`config.txt` is ignored by git, so your local paths and bucket name are not committed.

`LOG_DIRECTORY` may be absolute or relative. Relative paths are resolved against the script's directory, so manual runs and cron runs log to the same place.

Other settings in `config.example.txt`:

| Setting | Purpose |
| --- | --- |
| `MIN_SOURCE_FILES` | Refuse to run when the source has fewer files than this. Set it well below your normal count to catch an unmounted drive or an empty library. |
| `REQUIRE_MOUNT` | Set to `true` when `SOURCE_DIR` itself is a mountpoint that must be mounted. |
| `DB_BACKUP_DIR` | Directory containing Immich's `.sql.gz` dumps. Set to `""` to disable database backups. |
| `DB_BACKUP_PREFIX` | S3 prefix for dumps (default `backups/db`). Must stay Standard storage, not Deep Archive. If `BUCKET_PATH` includes a sub-path, set `db_backup_key_prefix` in `terraform.tfvars` to match (e.g. `backup/backups/db/`). |
| `DB_BACKUP_MAX_AGE` | Only upload dumps newer than this (default `90d`), so expired dumps are not re-uploaded. |
| `DB_BACKUP_MIN_AGE` | Skip dumps modified more recently than this (default `5m`), so a dump still being written is not uploaded half-finished. |
| `DB_BACKUP_FRESH_DAYS` | Fail the run when the newest dump is older than this (default 8 days), so an Immich backup that silently stopped is caught. |
| `LOG_RETENTION_DAYS` | How long to keep local log files (default 90 days). |

The script is safe to run from cron and by hand at the same time: a `flock` lock makes a second run exit immediately, and `PATH` is set internally so `rclone`, `aws` and `flock` are found even with cron's minimal environment.

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

The filename still says "daily" for historical reasons; the schedule above is weekly. Keep it weekly (or run it more often) — the alarm expects a run at least every 8 days.

If a tool lives somewhere unusual, use its full path or define `PATH` at the top of the crontab; the script already adds the common install locations (`/usr/local/bin`, `/snap/bin`, `~/.local/bin`, and the system paths).

After saving, verify the entry was installed:

```bash
crontab -l
```

It is also worth running the script manually once before relying on cron so any `rclone`, AWS, or config issues can be fixed interactively.

## Alerting
The script publishes a `BackupSuccess` metric to the `MediaBackup` CloudWatch namespace: `1` on success and `0` on failure. The alarm in `terraform/` evaluates one day at a time and goes to `ALARM` when **8 consecutive days** are breaching, where a day is breaching if it reported `0` or had no data (`treat_missing_data = "breaching"`).

That window is sized for a weekly schedule: the 7 quiet days between runs stay below the threshold, a failed run adds an eighth breaching day, and a run that never happens is caught on day 8. A longer (7-day) alarm period would line up with the schedule only by coincidence and produce false alarms after a single missed run.

Set notification targets in `terraform.tfvars`:

```terraform
alert_email        = "you@example.com"
# alert_phone_number = "+15551234567"
```

* Email is the cheapest path: the first 1,000 SNS email deliveries per month are free.
* SMS is opt-in because it has no free tier (~$0.00645 per US message plus carrier fees).

**The email subscription must be confirmed or no alert is ever delivered.** AWS sends a one-time confirmation link; the subscription stays in `PendingConfirmation` until it is clicked. Verify it after applying Terraform:

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:backup-failure-alerts" \
  --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}'
```

To resend the confirmation email, run the subscribe command again with the same address:

```bash
aws sns subscribe \
  --topic-arn "arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:backup-failure-alerts" \
  --protocol email \
  --notification-endpoint you@example.com
```

The alarm's namespace must match the script's namespace (`MediaBackup`). If you change one, change the other, or the alarm will sit in `ALARM` forever because it never receives data.

After applying Terraform, give the alarm one evaluation cycle to clear; run the script manually if it stays in `ALARM` because no metric has been published for 8 days.

## CloudWatch Dashboard
Terraform creates a `media-backup` dashboard with the alarm status, backup success history, S3 bucket size and object count, SNS deliveries, and estimated AWS charges. Set `enable_dashboard = false` in `terraform.tfvars` if you do not want it.

Costs: dashboards are free for the first three per account and $3/month after that. The S3 graphs use only the free daily storage metrics; S3 request metrics are deliberately not used because CloudWatch bills those as custom metrics.

## Costs
The setup is designed to stay cheap:

| Item | Cost |
| --- | --- |
| S3 Glacier Deep Archive storage | $0.00099/GB-month (~$1.01/TB) |
| PUT requests to Deep Archive | $0.05 per 1,000 (initial upload of ~20k files is about $1) |
| S3 Standard storage for database dumps | $0.023/GB-month (a few GB of dumps is a few cents/month) |
| LIST requests | $0.005 per 1,000 requests (a weekly run is a few hundred requests, well under $0.01) |
| CloudWatch custom metric | $0.30/month (first 10 free) |
| CloudWatch alarm | $0.10/month (first 10 standard alarms free) |
| CloudWatch dashboard | Free for the first 3, then $3/month |
| SNS email | Free for the first 1,000/month |
| SNS SMS | ~$0.00645/message in the US plus carrier fees |

Deep Archive has a **180-day minimum storage duration**. Deleting an object earlier is still billed for the remainder of the 180 days. Because media is copied with `rclone copy`, normal runs never delete anything; the minimum duration only matters when you prune manually or overwrite a changed file. Database dumps live in Standard storage, where there is no minimum duration, and expire after `db_backup_retention_days` (default 90).

## Pruning the Archive
Deleted photos stay in the archive on purpose. To find objects that no longer exist locally, run the check with the same exclusions as the backup. Excluding `/backups/**` is essential: database dumps are stored under `backups/db/`, not at the matching local path, so an unfiltered check would list every dump as "missing from source" and the delete step would wipe them.

```bash
rclone check "$SOURCE_DIR" "$BUCKET_PATH" --size-only \
  --exclude "/thumbs/**" --exclude "**/thumbs/**" --exclude "/backups/**" \
  --missing-on-src /tmp/only-in-s3.txt
```

Review that list, then delete exactly those objects (`--files-from-raw` overrides other filters, so it must be used alone):

```bash
rclone delete "$BUCKET_PATH" --files-from-raw /tmp/only-in-s3.txt --dry-run
rclone delete "$BUCKET_PATH" --files-from-raw /tmp/only-in-s3.txt
```

Paths in the list are relative to `$BUCKET_PATH`, which is why both commands use the same destination.

Remember the 180-day Deep Archive minimum: pruning recently uploaded objects still bills for the full 180 days.

## Restoring
Media is in Deep Archive and must be thawed before it can be downloaded. A bulk restore is the cheapest option:

```bash
aws s3api restore-object \
  --bucket YOUR_BUCKET \
  --key "immich_files/..." \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Bulk"}}'
```

Bulk restores can take up to 48 hours. `Days` is how long the restored copy stays downloadable after the thaw finishes. For many objects, loop over the keys (or use S3 Batch Operations); restoring one object at a time by hand does not scale to a library.

Then copy the objects back with `rclone copy` from a `s3:` remote whose storage class allows reads, or use `aws s3 cp --recursive` for a prefix.

Database dumps are in Standard storage, so they can be downloaded immediately:

```bash
rclone copy "s3:YOUR_BUCKET/backups/db" ./restore/
gunzip -c ./restore/immich-db-backup-*.sql.gz | psql ...
```

Test a restore before you need one. A backup that has never been restored is only a hypothesis.

Restoring is a separate cost: $0.02/GB for a standard restore (up to 12 hours) or $0.0025/GB for bulk (up to 48 hours), plus request and egress charges ($0.09/GB after the first 100 GB/month).

## Terraform Included
The terraform included here includes the AWS infra needed as a part of the backup process to S3 including:

* A S3 Bucket with public access blocked
* SSE-S3 encryption for the bucket
* Bucket lifecycle rules: abort incomplete multipart uploads, expire old database dumps
* IAM Policy for the bucket
* IAM User for my linux machine to connect to the bucket for backup
* CloudWatch metric alarm and SNS topic for failure notifications
* CloudWatch dashboard for backup and bucket stats

The provider is pinned to `us-east-1`. The script publishes its metric to the region in `AWS_REGION`, and CloudWatch alarms are regional, so if you change one, change the other (the provider block in `terraform/main.tf` and `AWS_REGION` in `config.txt`).

Confidential information like the AWS account is kept in a `terraform.tfvars` file which is in the form:

```terraform
my_account_id = "123456789012"
my_unique_uid = "example"
alert_email   = "you@example.com"
```

*In OtherBackupMethods.md two other alternative options for backup are provided, pure S3 and Backblaze.*
