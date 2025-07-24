output "budget_name" {
  description = "Name of the created budget"
  value       = aws_budgets_budget.account_budget.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.cpu_monitor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.cpu_monitor.arn
}