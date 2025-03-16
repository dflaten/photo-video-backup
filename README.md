# Photo Video Backup Scripts and Process

Scripts and programs to automate the backup of my personal photos and videos. I'm using [immich](https://immich.app/) for image storage and
backing up a copy to the cloud for long term storage.

Currently I have ~21,000 photos and 1,900 videos to store and I've decided to use S3 to back them up as the costs aren't too bad.

## Backup Process
I will use [restic](https://restic.readthedocs.io/en/stable/index.html) to backup my photos/videos and the database from immich to S3.

You may find the aws cli useful for verification on your immich machine, you can install with snap by using:
`snap install aws-cli --classic`

## Terraform Included
The terraform included here includes the AWS infra needed as a part of the backup process to S3 including:

* A S3 Bucket
* IAM Policy for the bucket
* IAM User for my linux machine to connect to the bucket for backup.

Confidential information like the AWS account is kept in a `terraform.tfvars` file which is in the form:

```terraform
my_account_id = "123456789012"
```

*In OtherBackupMethods.md I've outlined how to do so with two other possible options , pure S3 and Backblaze.*
