locals {
  # Map of Kubernetes major.minor to cluster-autoscaler release
  # Taken from https://github.com/kubernetes/autoscaler/releases as of 2020-06-09
  versions = {
    "1.17" = "1.17.2"
  }
}

data "aws_region" "current" {}
resource "kubernetes_storage_class" "topology-aware-ebs" {
  provider = kubernetes.aws_eks_cluster

  metadata {
    name = "topology-aware-ebs"
  }

  storage_provisioner = "kubernetes.io/aws-ebs"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp2"
    fsType    = "ext4"
    encrypted = true
  }
}

resource "kubernetes_namespace" "cluster_autoscaler" {
  provider = kubernetes.aws_eks_cluster
  metadata {
    name = "cluster-autoscaler"

    annotations = {

      # Placeholders so ignore_changes works
      "cattle.io/status"                          = ""
      "lifecycle.cattle.io/create.namespace-auth" = ""
    }

    labels = {
      # Placeholders so ignore changes works
      "field.cattle.io/projectId" = ""
    }
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations["cattle.io/status"],
      metadata.0.annotations["lifecycle.cattle.io/create.namespace-auth"],
      metadata.0.labels["field.cattle.io/projectId"],
    ]
  }
}

locals {
  ns = kubernetes_namespace.cluster_autoscaler.metadata.0.name

  tags = merge(
    var.tags,
    {
      "Cluster" = var.name,
    }
  )
}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.name}-cluster-autoscaler-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${aws_iam_openid_connect_provider.cluster.arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity"
    }
  ]
}
EOF

  tags = merge(
    local.tags,
    {
      "Name"                                 = "${var.name}-cluster-autoscaler-role",
      "kubernetes.io/cluster/${var.name}" = "owned",
    },
  )
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "${var.name}-cluster-autoscaler-policy"
  role = aws_iam_role.cluster_autoscaler.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
resource "helm_release" "cluster_autoscaler" {
  provider = helm.aws_eks_cluster
  name       = "cluster-autoscaler"
  repository = "https://kubernetes-charts.storage.googleapis.com"
  namespace  = local.ns
  chart      = "cluster-autoscaler"
  version    = "7.3.2"

  values = [<<EOF
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: nodetype
          operator: In
          values: ["system"]
autoDiscovery:
  clusterName: ${var.name}
  tags: ["kubernetes.io/cluster/{{ .Values.autoDiscovery.clusterName }}"]
awsRegion: ${data.aws_region.current.name}
cloudProvider: aws
extraArgs: {}
extraEnv: {}
fullnameOverride: cluster-autoscaler
image:
  repository: us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler
  tag: v${local.versions[var.eks_version]}
rbac:
  create: true
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: ${aws_iam_role.cluster_autoscaler.arn}
resources:
  limits:
    cpu: 100m
    memory: 300Mi
  requests:
    cpu: 100m
    memory: 300Mi
tolerations:
- key: "node-role.kubernetes.io/system"
  operator: Exists
EOF
  ]
}
