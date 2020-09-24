variable "name" {
  description = "Name to use for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC into which the cluster and related resources will be placed"
}

variable "public_subnet_ids" {
  description = "List of IDs of public subnets to attach the cluster to"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "List of IDs of private subnets to attach the cluster to"
  type        = list(string)
}

variable "enabled_log_types" {
  description = "List of control plane log types to enable for the VPC cluster"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Log retention for VPC control plane logs, in days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to add to EKS cluster and related resources"
  type        = map(string)
}

variable "system_node_group" {
  description = "System node group configuration"
  type = object({
    ec2_instance_type = string # EC2 instance type to use for the nodes
    num_nodes         = number # Initial number of nodes for the auto-scaling group
    min_nodes         = number # Minimum number of nodes for the auto-scaling group
    max_nodes         = number # Maximum number of nodes for the auto-scaling group
  })
  default = {
    ec2_instance_type = "m5.large"
    num_nodes         = 3
    min_nodes         = 1
    max_nodes         = 6
  }
}

variable "application_node_group" {
  description = "Application node group configuration"
  type = object({
    ec2_instance_type = string      # EC2 instance type to use for the nodes
    num_nodes         = number      # Initial number of nodes for the auto-scaling group
    min_nodes         = number      # Minimum number of nodes for the auto-scaling group
    max_nodes         = number      # Maximum number of nodes for the auto-scaling group
    spot_price        = string      # The maximum price to use for reserving spot instances.  Set to null or empty if not using spot instance.
    labels            = map(string) # Labels to apply to the node group
  })
  default = {
    ec2_instance_type = "m5.large"
    num_nodes         = 3
    min_nodes         = 1
    max_nodes         = 6
    spot_price        = null
    labels            = {}
  }
}

variable "extra_node_groups" {
  description = "Extra node groups to run in addition to the default node groups"
  type = map(object({
    node_type                = string       # the type of node.  Value will be used as a value for nodetype label
    ec2_instance_type        = string       # EC2 instance type to use for the nodes
    policy                   = string       # iam policy doc in json to add to the node group's IAM role policy
    extra_security_group_ids = list(string) # extra security groups to add the nodes to
    extra_kubelet_args       = string       # Extra arguments to pass to kubelet (for node labels, etc.)
    num_nodes                = number       # Initial number of nodes for the auto-scaling group
    min_nodes                = number       # Minimum number of nodes for the auto-scaling group
    max_nodes                = number       # Maximum number of nodes for the auto-scaling group
    is_public                = bool         # Whether the nodes should be in the public subnets
    spot_price               = string       # The maximum price to use for reserving spot instances.  Set to null or empty if not using spot instance.
    labels                   = map(string)  # Labels to apply to the node group
    taints                   = map(string)  # Taints to apply to the node group
  }))
  default = {}
}

variable "iam_role_rbac_map" {
  description = "A list of objects defining IAM role mapping to RBAC groups"
  type = list(object({
    iam_role_arn = string
    rbac_groups  = list(string)
  }))
}

variable "eks_version" {
  description = "EKS Version to deploy. Used for the EKS cluster and to lookup the EKS Node AMI"
  type        = string
}
