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
- **Lambda**: Comprehensive resource shutdown when CPU hits 100% or budget is breached
- **CloudWatch**: Monitors CPU metrics and triggers Lambda
- **SNS**: Triggers Lambda when budget reaches 100% ($2000)
- **IAM**: Provides necessary permissions for Lambda execution

## Lambda Shutdown Actions

When triggered, the Lambda function automatically:

- **EC2 Instances**: Stops instances with 100% CPU utilization
- **CloudFront Distributions**: Disables all active distributions
- **API Gateway**: Throttles all REST API endpoints to 0 requests/second
- **Bedrock Agents**: Disables all prepared agents
- **Lambda Functions**: Sets provisioned concurrency to 0 (except monitoring function)
- **ECS Services**: Scales desired count to 0 for all services
- **Application Load Balancers**: Deletes all active ALBs

## Triggers

1. **Budget Alert**: Automatically triggers when spending reaches $2000 (100% of budget)
2. **High CPU**: Triggers when EC2 instances hit 100% CPU utilization for 10 minutes

## Note

Storage resources (EBS volumes, S3) are not affected by the Lambda function to prevent data loss.