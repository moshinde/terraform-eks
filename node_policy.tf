data "aws_iam_policy_document" "node_default" {

  statement {
    effect = "Allow"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:GetManifest",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstanceStatus",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ds:CreateComputer",
      "ds:DescribeDirectories"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::aws-ssm-us-east-1/*",
      "arn:aws:s3:::aws-windows-downloads-us-east-1/*",
      "arn:aws:s3:::amazon-ssm-us-east-1/*",
      "arn:aws:s3:::amazon-ssm-packages-us-east-1/*",
      "arn:aws:s3:::us-east-1-birdwatcher-prod/*",
      "arn:aws:s3:::aws-ssm-us-west-2/*",
      "arn:aws:s3:::aws-windows-downloads-us-west-2/*",
      "arn:aws:s3:::amazon-ssm-us-west-2/*",
      "arn:aws:s3:::amazon-ssm-packages-us-west-2/*",
      "arn:aws:s3:::us-west-2-birdwatcher-prod/*"
    ]
  }
}

data "aws_iam_policy_document" "system_extra" {
  # Allow this role to assume itself (to generate temporary credentials with a shorter TTL or a different session name)
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-system-eks-node"]
  }
  # Allow this role to assume the kiam server role
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-kiam-server", ]
  }
}
