# Bootstrapping remote Terraform state (one-time, manual)

Terraform needs somewhere to store state that both your laptop and CI can
reach. Create it once, by hand, **before** the S3 backend block in
`terraform/providers.tf` is uncommented:

```bash
aws s3api create-bucket \
  --bucket YOUR_UNIQUE_BUCKET_NAME \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1

aws s3api put-bucket-versioning \
  --bucket YOUR_UNIQUE_BUCKET_NAME \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name YOUR_LOCK_TABLE_NAME \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Then in `terraform/providers.tf`, uncomment the `backend "s3" {}` block, fill
in the bucket/table names, and run:

```bash
cd terraform
terraform init -migrate-state
```

Why this matters for a "hireable" repo: without remote state, every
`terraform apply` from CI would create its own local state file and drift
from what your laptop thinks exists -- a common first-week outage in real
teams. This is also why `.tfstate` files are gitignored: they can contain
secrets in plaintext.
