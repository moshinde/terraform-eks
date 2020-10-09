locals {
  k8s_label_prefix = "k8s.io/cluster-autoscaler/node-template/label"
  k8s_taint_prefix = "k8s.io/cluster-autoscaler/node-template/taint"
  no_spot_price    = "$$$"
  spot_taints_args = "--register-with-taints=spotInstance=true:PreferNoSchedule"

  node_groups = {
    system : {
      node_type                = "system"
      policy                   = data.aws_iam_policy_document.system_extra.json
      extra_security_group_ids = []
      labels                   = { "nodetype" = "system" }
      taints                   = { "node-role.kubernetes.io/system" = "true:NoSchedule" }
      extra_kubelet_args       = ""
      ec2_instance_type        = var.system_node_group.ec2_instance_type
      num_nodes                = var.system_node_group.num_nodes
      min_nodes                = var.system_node_group.min_nodes
      max_nodes                = var.system_node_group.max_nodes
      is_public                = false
      spot_price               = null
    },
    application : {
      node_type                = "application"
      policy                   = ""
      extra_security_group_ids = []
      labels                   = merge(var.application_node_group.labels, { "nodetype" = "application" })
      taints                   = {}
      extra_kubelet_args       = ""
      ec2_instance_type        = var.application_node_group.ec2_instance_type
      num_nodes                = var.application_node_group.num_nodes
      min_nodes                = var.application_node_group.min_nodes
      max_nodes                = var.application_node_group.max_nodes
      is_public                = false
      spot_price               = var.application_node_group.spot_price
    }
  }

  merged_node_groups = merge(var.extra_node_groups, local.node_groups)
}

data "aws_iam_policy_document" "node_group" {
  for_each = local.merged_node_groups

  source_json   = data.aws_iam_policy_document.node_default.json
  override_json = each.value.policy
}

resource "aws_launch_configuration" "node_groups" {
  for_each = local.merged_node_groups

  associate_public_ip_address = each.value.is_public
  iam_instance_profile        = aws_iam_instance_profile.node_groups[each.key].name
  image_id                    = data.aws_ami.eks_node.id
  instance_type               = each.value.ec2_instance_type
  name_prefix                 = "${var.name}-${each.key}-eks-worker"
  security_groups             = concat([aws_security_group.eks_node.id], each.value.extra_security_group_ids)
  spot_price                  = each.value.spot_price
  user_data                   = <<EOT
#!/bin/bash -xe
LABELS="${join(",", [for k, v in each.value.labels : "${k}=${v}"])}"
TAINTS="${join(",", [for k, v in each.value.taints : "${k}=${v}"])}"

LIFECYCLE=${coalesce(each.value.spot_price, local.no_spot_price) == local.no_spot_price ? "OnDemand" : "Ec2Spot"}

/etc/eks/bootstrap.sh ${var.name} \
  --apiserver-endpoint ${aws_eks_cluster.cluster.endpoint} \
  --b64-cluster-ca ${aws_eks_cluster.cluster.certificate_authority.0.data} \
  --kubelet-extra-args "%{if length(each.value.labels) > 0~}--node-labels $LABELS %{endif~} --node-labels nodetype=${each.value.node_type},lifecycle=$LIFECYCLE ${coalesce(each.value.spot_price, local.no_spot_price) == local.no_spot_price ? "" : local.spot_taints_args} %{if length(each.value.taints) > 0~}--register-with-taints=$TAINTS %{endif~} ${each.value.extra_kubelet_args}"
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm

EOT

  root_block_device {
    volume_type = "gp2"
    volume_size = 100
    encrypted   = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "node_groups" {
  for_each = local.merged_node_groups

  launch_configuration = aws_launch_configuration.node_groups[each.key].name
  desired_capacity     = each.value.num_nodes
  max_size             = each.value.max_nodes
  min_size             = each.value.min_nodes
  name                 = "${var.name}-${each.key}-eks-node-group"
  termination_policies = ["OldestLaunchConfiguration", "NewestInstance", "Default"]
  vpc_zone_identifier  = each.value.is_public ? data.aws_subnet_ids.public_subnets.ids : data.aws_subnet_ids.private_subnets.ids

  lifecycle {
    ignore_changes = [
      desired_capacity,
    ]
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-${each.key}-eks-node-group"
    propagate_at_launch = true
  }

  tag {
    key                 = "Cluster"
    value               = var.name
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.name}"
    value               = "owned"
    propagate_at_launch = true
  }

  # lifecycle label to indicate spot or ondemand
  tag {
    key                 = "${local.k8s_label_prefix}/lifecycle"
    value               = coalesce(each.value.spot_price, local.no_spot_price) == local.no_spot_price ? "OnDemand" : "Ec2Spot"
    propagate_at_launch = true
  }

  # spot instance taint
  tag {
    key                 = "${local.k8s_taint_prefix}/spotInstance"
    value               = coalesce(each.value.spot_price, local.no_spot_price) == local.no_spot_price ? "false:PreferNoSchedule" : "true:PreferNoSchedule"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  dynamic "tag" {
    for_each = each.value.taints
    content {
      key                 = "${local.k8s_taint_prefix}/${tag.key}"
      value               = tag.value
      propagate_at_launch = true
    }
  }

  dynamic "tag" {
    for_each = each.value.labels
    content {
      key                 = "${local.k8s_label_prefix}/${tag.key}"
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_iam_role" "node_groups" {
  for_each = local.merged_node_groups

  name = "${var.name}-${each.key}-eks-node-group"

  assume_role_policy = <<EOF
{ "Version": "2012-10-17",
  "Statement": [ {
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  } ] }
EOF

  tags = merge(var.tags, { Name : "${var.name}-${each.key}-eks-node-group" })
}

resource "aws_iam_role_policy" "node_groups" {
  for_each = local.merged_node_groups

  name = "${var.name}-${each.key}-eks-node-group"
  role = aws_iam_role.node_groups[each.key].name

  policy = data.aws_iam_policy_document.node_group[each.key].json
}

# Provides permissions needed for worker nodes to find and attach to the
# cluster (see aws-auth.tf for the other thing needed to allow them to
# connect).
resource "aws_iam_role_policy_attachment" "eks_worker" {
  for_each = local.merged_node_groups

  role       = aws_iam_role.node_groups[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Provides permissions needed for workers to use the VPC networking (each pod
# gets an IP in the VPCs subnets).
resource "aws_iam_role_policy_attachment" "eks_cni" {
  for_each = local.merged_node_groups

  role       = aws_iam_role.node_groups[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Provides permissions for workers to access ECR to pull container images.
resource "aws_iam_role_policy_attachment" "ecr_ro" {
  for_each = local.merged_node_groups

  role       = aws_iam_role.node_groups[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "node_groups" {
  for_each = local.merged_node_groups

  name = "${var.name}-${each.key}-eks-node-group"
  role = aws_iam_role.node_groups[each.key].name
}

resource "aws_security_group" "eks_node" {
  name        = "${var.name}-eks-node"
  description = "Security group for all nodes in the ${var.name} cluster"
  vpc_id      = data.aws_vpc.primary_vpc.id

  tags = merge(var.tags, {
    Name                                = "${var.name}-eks-node"
    "kubernetes.io/cluster/${var.name}" = "shared" # Required to prevent k8s from thinking it needs to add rules to the security group (see https://github.com/kubernetes/legacy-cloud-providers/blob/release-1.17/aws/aws.go#L4118)
  })
}

resource "aws_security_group_rule" "eks_node_egress_all" {
  security_group_id = aws_security_group.eks_node.id
  type              = "egress"
  description       = "Allow all outbound"
  protocol          = "all"
  from_port         = 0
  to_port           = 65535
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eks_node_ingress_self" {
  security_group_id        = aws_security_group.eks_node.id
  type                     = "ingress"
  description              = "Allow nodes to communicate with each other"
  protocol                 = "all"
  from_port                = 0
  to_port                  = 65535
  source_security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "eks_node_ingress_cluster" {
  security_group_id        = aws_security_group.eks_node.id
  type                     = "ingress"
  description              = "Allow node Kubelets and pods to receive communication from the cluster control plane"
  protocol                 = "tcp"
  from_port                = 1025
  to_port                  = 65535
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "eks_node_https_ingress_cluster" {
  security_group_id        = aws_security_group.eks_node.id
  type                     = "ingress"
  description              = "Allow node Kubelets and pods to receive HTTPS communication from the cluster control plane"
  protocol                 = "tcp"
  from_port                = 443
  to_port                  = 443
  source_security_group_id = aws_security_group.cluster.id
}
