# ==========================================
# SES Domain Identity + DKIM
# ==========================================
resource "aws_ses_domain_identity" "main" {
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

resource "aws_route53_record" "ses_verification" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.main.verification_token]
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.main.zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# ==========================================
# Lambda IAM Role
# ==========================================
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-notify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy" "lambda_ses" {
  name = "lambda-ses-send"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ses:SendEmail"
      Resource = "*"
    }]
  })
}

# ==========================================
# Lambda Function
# ==========================================
# ==========================================
# Lambda Function
# ==========================================
resource "aws_lambda_function" "notify" {
  function_name = "${var.project_name}-notify"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  filename = "lambda.zip"

  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      SES_SENDER = "noreply@${var.domain_name}"
    }
  }

  tags = { Name = "${var.project_name}-notify-lambda" }
}

# ==========================================
# API Gateway HTTP API
# ==========================================
resource "aws_apigatewayv2_api" "notify_api" {
  name          = "${var.project_name}-notify-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.notify_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.notify.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "notify" {
  api_id    = aws_apigatewayv2_api.notify_api.id
  route_key = "POST /notify"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.notify_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notify_api.execution_arn}/*/

