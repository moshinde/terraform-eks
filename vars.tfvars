name="hhh-test"
eks_version="1.17"
tags = {
    Owner        = "Monica Shinde"
    BusinessUnit = "HHH"
    Environment  = "sandbox"
    Application  = "test-Applications"
}

iam_role_rbac_map = [
    {
      iam_role_arn = ""
      rbac_groups  = ["system:masters"]
    },
    {
      iam_role_arn = ""
      rbac_groups  = ["system:masters"]
    }
]