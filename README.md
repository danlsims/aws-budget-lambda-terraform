# AWS Budget and CPU Monitor Terraform Project

This Terraform project creates:
- AWS Budget for $2000 across all services
- Lambda function to stop EC2 instances with 100% CPU utilization
- CloudWatch alarms and events to trigger the Lambda

## Setup

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Update the email address in `terraform.tfvars`
3. Initialize and apply Terraform:

```bash
terraform init
terraform plan
terraform apply
```

## Components

- **Budget**: Monitors spending across all AWS services with $2000 limit
- **Lambda**: Stops EC2 instances when CPU hits 100%
- **CloudWatch**: Monitors CPU metrics and triggers Lambda
- **IAM**: Provides necessary permissions for Lambda execution

## Note

Storage resources (EBS volumes, S3) are not affected by the Lambda function.