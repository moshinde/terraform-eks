
data "aws_caller_identity" "current" {}
data "aws_vpc" "primary_vpc" {
  tags = {
    Name = "${var.name}-vpc"
  }
}

data "aws_subnet_ids" "private_subnets" {
  vpc_id = data.aws_vpc.primary_vpc.id

  tags = {
    Name = "${var.name}-private*"
  }
}

data "aws_subnet_ids" "public_subnets" {
  vpc_id = data.aws_vpc.primary_vpc.id

  tags = {
    Name = "${var.name}-public*"
  }
}
locals{
  iam_role_rbac_map =[
    {
      iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/FullAccess"
      rbac_groups  = ["system:masters"]
    },
    {
      iam_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/PowerUserAccess"
      rbac_groups  = ["system:masters"]
    }
  ]
}
resource "aws_eks_cluster" "cluster" {
  name     = var.name
  role_arn = aws_iam_role.control_plane.arn
  version  = var.eks_version

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
    subnet_ids              = concat(sort(data.aws_subnet_ids.private_subnets.ids), sort(data.aws_subnet_ids.public_subnets.ids))
  }

  enabled_cluster_log_types = var.enabled_log_types

  tags = var.tags

  depends_on = [
    # Ensure IAM permissions stick around until cluster is deleted
    aws_iam_role_policy_attachment.control_plane_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.control_plane_AmazonEKSServicePolicy,
    aws_iam_role_policy_attachment.eks_worker,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_ro,
    aws_iam_role_policy.node_groups,

    # Ensure SG rules stick around until cluster is deleted
    aws_security_group_rule.cluster_self_ingress,
    aws_security_group_rule.cluster_all_egress,
    aws_security_group_rule.cluster_ingress_nodes,
    aws_security_group_rule.cluster_egress_nodes,
    aws_security_group_rule.eks_node_egress_all,
    aws_security_group_rule.eks_node_ingress_self,
    aws_security_group_rule.eks_node_ingress_cluster,
    aws_security_group_rule.eks_node_https_ingress_cluster,

    # Avoid automatically-created log group without encryption enabled
    aws_cloudwatch_log_group.logs,
  ]
}

resource "aws_iam_role" "control_plane" {
  name = "${var.name}-eks-control-plane"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "eks.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF

  tags = merge(var.tags, { Name : "${var.name}-eks-control-plane" })
}

resource "aws_iam_role_policy_attachment" "control_plane_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.control_plane.name
}

resource "aws_iam_role_policy_attachment" "control_plane_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.control_plane.name
}

resource "aws_security_group" "cluster" {
  name        = "${var.name}-eks-cluster"
  description = "${var.name} EKS control plane and hosted node group security group"
  vpc_id      = data.aws_vpc.primary_vpc.id
  tags        = merge(var.tags, { Name : "${var.name}-eks-cluster" })
}

resource "aws_security_group_rule" "cluster_self_ingress" {
  security_group_id = aws_security_group.cluster.id
  description       = "Allow ${var.name} control plane to connect to itself and hosted node groups"
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  self              = true
}

resource "aws_security_group_rule" "cluster_all_egress" {
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "cluster_ingress_nodes" {
  description              = "Allow HTTPS in from node group"
  security_group_id        = aws_security_group.cluster.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "cluster_egress_nodes" {
  description              = "Allow outgoing connections to node group"
  security_group_id        = aws_security_group.cluster.id
  type                     = "egress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.cluster.id
}

provider "kubernetes" {
  alias                  = "aws_eks_cluster"
  host                   = aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

provider "helm" {
  alias = "aws_eks_cluster"
  kubernetes {
    host                   = aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    load_config_file       = false
  }
}
resource "aws_cloudwatch_log_group" "logs" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  tags = var.tags
}

data "external" "thumb" {
  program = ["kubergrunt", "eks", "oidc-thumbprint", "--issuer-url", aws_eks_cluster.cluster.identity.0.oidc.0.issuer]
}

### OIDC Identity Provider config
resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.external.thumb.result.thumbprint]
  url             = aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}