terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# SNS topic for budget alerts
resource "aws_sns_topic" "budget_alarm" {
  name = "budget-alarm-topic"
}

# SNS subscription to trigger Lambda
resource "aws_sns_topic_subscription" "budget_lambda" {
  topic_arn = aws_sns_topic.budget_alarm.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.cpu_monitor.arn
}

# Budget for $2000 across all services
resource "aws_budgets_budget" "account_budget" {
  name         = "account-wide-budget"
  budget_type  = "COST"
  limit_amount = var.budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  cost_filter {
    name   = "Service"
    values = ["*"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator   = "GREATER_THAN"
    threshold            = 100
    threshold_type       = "PERCENTAGE"
    notification_type    = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget_alarm.arn]
  }
}

# Budget Action to trigger Lambda when budget is breached
resource "aws_budgets_budget_action" "shutdown_action" {
  budget_name    = aws_budgets_budget.account_budget.name
  action_type    = "RUN_SSM_DOCUMENTS"
  approval_model = "AUTOMATIC"
  
  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }
  
  definition {
    ssm_action_definition {
      action_sub_type = "STOP_EC2_INSTANCES"
      region         = var.aws_region
      instance_ids   = ["*"]
    }
  }
  
  subscriber {
    address           = var.notification_email
    subscription_type = "EMAIL"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "cpu-monitor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda to manage EC2 instances and access CloudWatch
resource "aws_iam_role_policy" "lambda_policy" {
  name = "cpu-monitor-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudfront:ListDistributions",
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution",
          "apigateway:GET",
          "apigateway:PATCH",
          "bedrock:ListAgents",
          "bedrock:UpdateAgent",
          "lambda:ListFunctions",
          "lambda:PutProvisionedConcurrencyConfig",
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:UpdateService",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:DeleteLoadBalancer"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "cpu_monitor" {
  filename         = "cpu_monitor.zip"
  function_name    = "cpu-monitor-lambda"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300

  depends_on = [data.archive_file.lambda_zip]
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "cpu_monitor.zip"
  source {
    content = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }
}

# CloudWatch Event Rule to trigger Lambda at 100% CPU utilization
resource "aws_cloudwatch_event_rule" "cpu_alarm_rule" {
  name        = "cpu-high-utilization-rule"
  description = "Trigger Lambda when CPU utilization is high"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM"]
      }
      alarmName = [{
        prefix = "HighCPUUtilization"
      }]
    }
  })
}

# CloudWatch Event Target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cpu_alarm_rule.name
  target_id = "TriggerLambdaFunction"
  arn       = aws_lambda_function.cpu_monitor.arn
}

# Permission for CloudWatch Events to invoke Lambda
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cpu_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cpu_alarm_rule.arn
}

# Permission for SNS to invoke Lambda
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cpu_monitor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.budget_alarm.arn
}

# CloudWatch Alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "HighCPUUtilization-EC2"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_lambda_function.cpu_monitor.arn]

  dimensions = {
    InstanceId = "*"
  }
}