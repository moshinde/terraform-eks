output "cluster" {
  value = aws_eks_cluster.cluster
}

output "cluster_name" {
  description = "The cluster name, specified in a way that forces dependency on the cluster, the node groups, and other essential resources"
  value = coalesce(
    aws_eks_cluster.cluster.id,
    join("", [for g in aws_autoscaling_group.node_groups : g.name]),
    kubernetes_config_map.aws_auth.id,
    aws_iam_openid_connect_provider.cluster.id,
  )
}

output "node_group_roles" {
  description = "Roles created for the cluster's node groups"
  value       = aws_iam_role.node_groups
}

output "oidc_provider" {
  description = "OIDC provider for use in creating assume role policies for Kubernetes service accounts"
  value       = aws_iam_openid_connect_provider.cluster
}

output "node_security_group" {
  description = "Security group"
  value       = aws_security_group.eks_node.id
}

output "kubeconfig" {
  description = "Kubeconfig file for connecting to the cluster with kubectl"
  value       = <<EOF
kind: Config
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "${var.name}"
        # Add a line like the following if you need to assume a role for auth (edit the role name of course)
        # - --role=arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/k8s-${var.name}-admin
      # Uncomment and set the profile to the appropriate one in your ~/.aws/credentials file
      # to choose the correct profile for auth (you can set a role to assume in your credentials
      # file instead of using the above profile line):
      # env:
      # - name: "AWS_PROFILE"
      #   value: "appropriate-account"
EOF
}