data "aws_region" "current" {}
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${var.alert_name}.zip"
  source_dir  = "${path.root}/lambda_function"
}

resource "aws_iam_role" "lambda_alert_role" {
  name = "${var.alert_name}-alert-role"

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

  tags = {
    Name = "${var.alert_name}alert-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_alert_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "alert_function" {
  filename         = "${var.alert_name}.zip"
  function_name    = "function_${var.alert_name}"
  role            = aws_iam_role.lambda_alert_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      GOOGLE_CHAT_WEBHOOK_URL = var.gchat_webhook
    }
  }

  tags = {
    Name = "${var.alert_name}"
  }
}
