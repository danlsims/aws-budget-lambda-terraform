variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "notification_email" {
  description = "Email address for budget notifications"
  type        = string
}

variable "budget_amount" {
  description = "Budget limit amount in USD"
  type        = string
  default     = "2000"
}