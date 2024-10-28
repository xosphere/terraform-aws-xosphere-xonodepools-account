data "aws_region" "current" {}

locals {
  version                                 = "0.1.0"
  xo_account_region                       = "us-west-2"
  api_token_arn = (var.secretsmanager_arn_override == null) ? format("arn:aws:secretsmanager:%s:%s:secret:customer/%s", local.xo_account_region, var.xo_account_id, var.customer_id) : var.secretsmanager_arn_override
  api_token_pattern = (var.secretsmanager_arn_override == null) ? format("arn:aws:secretsmanager:%s:%s:secret:customer/%s-??????", local.xo_account_region, var.xo_account_id, var.customer_id) : var.secretsmanager_arn_override
  kms_key_pattern                         = format("arn:aws:kms:%s:%s:key/*", local.xo_account_region, var.xo_account_id)
  organization_management_account_enabled = var.management_aws_account_id != ""
}

output "xonodepool_module_version" {
  value = local.version
}

data "aws_iam_policy_document" "xonodepool_controller_role_assume_policy" {
  # pod identity
  statement {
    sid = "AssumeViaPodIdentity"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    effect  = "Allow"

    principals {
      identifiers = ["pods.eks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "xonodepool_controller_role" {
  name               = "xosphere-xonodepool-role"
  assume_role_policy = data.aws_iam_policy_document.xonodepool_controller_role_assume_policy.json
}

resource "aws_iam_role_policy" "xonodepool_controller_role_policy" {
  name = "xosphere-xonodepool-role-policy"
  role = aws_iam_role.xonodepool_controller_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOperationsWithoutResourceRestrictions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAccountAttributes",
        "organizations:DescribeOrganization",
        "savingsplans:DescribeSavingsPlans",
        "savingsplans:DescribeSavingsPlanRates"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3ReadOnXosphereObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:*:s3:::xosphere-*/*",
        "arn:*:s3:::xosphere-*"
      ]
    },
    {
      "Sid": "AllowEc2Read",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeSpotPriceHistory"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSecretManagerOperations",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "${local.api_token_pattern}"
    },
    {
      "Sid": "AllowKmsOperations",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": "${local.kms_key_pattern}"
    },
%{ if local.organization_management_account_enabled }
    {
      "Sid": "AllowOrgKmsCmk",
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ],
      "Resource": "${join("", ["arn:*:kms:*:", var.management_aws_account_id, ":key/*"])}",
      "Condition": {
        "ForAnyValue:StringEquals": {
          "kms:ResourceAliases": "alias/XosphereMgmtCmk"
        }
      }
    },
%{ endif }
    {
      "Sid": "AllowCloudwatchOperationsInXosphereNamespace",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "cloudwatch:namespace": ["xosphere.io/XoNodePool/*"]
        }
      }
    }
  ]
}
EOF
}



# resource "aws_sqs_queue" "xosphere_aggregate_data_queue_dlq" {
#   name                       = "xosphere-aggregate-data-dlq"
#   visibility_timeout_seconds = 300
#   kms_master_key_id          = "alias/aws/sqs"
# }

# resource "aws_sqs_queue" "xosphere_aggregate_data_queue" {
#   name = "xosphere-aggregate-data"
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.xosphere_aggregate_data_queue_dlq.arn
#     maxReceiveCount     = 5
#   })
#   visibility_timeout_seconds = 1020
#   kms_master_key_id          = "alias/aws/sqs"
# }

# resource "aws_lambda_function" "xosphere_aggregate_data_processor_lambda" {
#   s3_bucket = local.s3_bucket
#   s3_key = "xonodepools/aggregate-data-processor-lambda-${local.version}.zip"
#   description = "Xosphere Aggregate Data Processor"
#   environment {
#     variables = {
#       SQS_QUEUE = aws_sqs_queue.xosphere_aggregate_data_queue.id
#       API_TOKEN_ARN = local.api_token_arn
#       ENDPOINT_URL = var.endpoint_url
#     }
#   }
#   function_name = "xosphere-aggregate-data-processor-lambda"
#   handler = "bootstrap"
#   memory_size = var.aggregate_data_processor_lambda_memory_size
#   role = aws_iam_role.xosphere_aggregate_data_processor_role.arn
#   runtime = "provided.al2"
#   architectures = [ "arm64" ]
#   timeout = var.aggregate_data_processor_lambda_timeout
#   depends_on = [ aws_cloudwatch_log_group.xosphere_aggregate_data_processor_cloudwatch_log_group ]
# }

# resource "aws_iam_role" "xosphere_aggregate_data_processor_role" {
#   assume_role_policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "AllowLambdaToAssumeRole",
#       "Effect": "Allow",
#       "Action": "sts:AssumeRole",
#       "Principal": { "Service": "lambda.amazonaws.com" }
#     }
#   ]
# }
# EOF
#   name               = "xosphere-aggregate-data-processor-lambda-role"
#   path               = "/"
# }

# resource "aws_iam_role_policy" "xosphere_aggregate_data_processor_policy" {
#   name   = "xosphere-aggregate-data-processor-lambda-policy"
#   role   = aws_iam_role.xosphere_aggregate_data_processor_role.id
#   policy = <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "AllowLogOperationsOnXosphereLogGroups",
#       "Effect": "Allow",
#       "Action": [
#         "logs:CreateLogStream",
#         "logs:PutLogEvents"
# 	    ],
#       "Resource": [
#         "${aws_cloudwatch_log_group.xosphere_aggregate_data_processor_cloudwatch_log_group.arn}",
#         "${aws_cloudwatch_log_group.xosphere_aggregate_data_processor_cloudwatch_log_group.arn}:log-stream:*"
#       ]
#     },
#     {
#         "Sid": "AllowSecretManagerOperations",
#         "Effect": "Allow",
#         "Action": [
#             "secretsmanager:GetSecretValue"
#         ],
#         "Resource": "${local.api_token_pattern}"
#     },
#     {
#         "Sid": "AllowSqsConsumeOnAggregateDataProcessorQueue",
#         "Effect": "Allow",
#         "Action": [
#             "sqs:ChangeMessageVisibility",
#             "sqs:DeleteMessage",
#             "sqs:GetQueueAttributes",
#             "sqs:ReceiveMessage",
#             "sqs:SendMessage"
#         ],
#         "Resource": [
#           "${aws_sqs_queue.xosphere_aggregate_data_queue.arn}"
#         ]
#     }
#   ]
# }
# EOF
# }

# resource "aws_iam_service_linked_role" "lambda" {
#   aws_service_name = "lambda.amazonaws.com"
# }

# resource "aws_cloudwatch_log_group" "xosphere_aggregate_data_processor_cloudwatch_log_group" {
#   name              = "/aws/lambda/xosphere-aggregate-data-processor-lambda"
#   retention_in_days = var.aggregate_data_processor_lambda_log_retention
# }

# resource "aws_lambda_event_source_mapping" "xosphere_aggregate_data_processor_event_source_mapping" {
#   batch_size = 1
#   enabled = true
#   event_source_arn = aws_sqs_queue.xosphere_aggregate_data_queue.arn
#   function_name = aws_lambda_function.xosphere_aggregate_data_processor_lambda.arn
#   depends_on = [ aws_iam_role.xosphere_aggregate_data_processor_role ]
# }

# resource "aws_lambda_permission" "xosphere_aggregate_data_processor_sqs_lambda_permission" {
#   action = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.xosphere_aggregate_data_processor_lambda.arn
#   principal = "sqs.amazonaws.com"
#   source_arn = aws_sqs_queue.xosphere_aggregate_data_queue.arn
#   statement_id = "AllowExecutionFromSqs"
# }
