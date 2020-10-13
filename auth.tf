locals{
  iam_role_rbac_map = [
    {
      iam_role_arn = "arn:aws:iam::783486464333:role/FullAccess"
      rbac_groups  = ["system:masters"]
    },
    {
      iam_role_arn = "arn:aws:iam::783486464333:role/PowerUserAccess"
      rbac_groups  = ["system:masters"]
    }
  ]
}

# This config map defines which roles and users can access the kubernetes cluster.
resource "kubernetes_config_map" "aws_auth" {
  provider = kubernetes.aws_eks_cluster

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = <<EOF
%{for node_group in keys(local.merged_node_groups)~}
- rolearn: ${aws_iam_role.node_groups[node_group].arn}
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes
%{endfor~}
%{for rolemap in local.iam_role_rbac_map~}
- rolearn: ${rolemap.iam_role_arn}
  username: aws:{{AccountID}}:instance:{{SessionName}}
  groups:
  ${indent(4, yamlencode(rolemap.rbac_groups))}
%{endfor~}
EOF
    mapUsers = <<EOF
EOF
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name $CLUSTER && kubectl -n kube-system patch deployment/coredns -p \"$PATCH\" --type=merge"
    environment = {
      KUBECONFIG = "${path.module}/kubeconfig"
      CLUSTER    = var.name
      PATCH      = local.coredns_patch
    }
  }
}

locals {
  coredns_patch = jsonencode({
    spec = {
      template = {
        spec = {
          tolerations = [{
            key      = "node-role.kubernetes.io/system"
            operator = "Exists"
          }]
          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [{
                  matchExpressions = [{
                    key      = "nodetype"
                    operator = "In"
                    values   = ["system"]
                  }]
                }]
              }
            }
          }
        }
      }
    }
  })
}
