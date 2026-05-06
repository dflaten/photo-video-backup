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
    Remote name: This becomes your RCLONE_REMOTE value

Then update `config.txt` with the appropriate values. 

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

## Terraform Included
The terraform included here includes the AWS infra needed as a part of the backup process to S3 including:

* A S3 Bucket
* IAM Policy for the bucket
* IAM User for my linux machine to connect to the bucket for backup.

Confidential information like the AWS account is kept in a `terraform.tfvars` file which is in the form:

```terraform
my_account_id = "123456789012"
```

*In OtherBackupMethods.md two other alternative options for backup are provided, pure S3 and Backblaze.*
