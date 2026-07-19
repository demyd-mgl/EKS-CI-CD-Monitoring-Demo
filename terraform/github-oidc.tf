variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, as \"org/repo\" (e.g. \"myuser/devops-eks-demo\")"
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    Whether to create the GitHub OIDC provider in this AWS account.
    Set to false only if a provider for https://token.actions.githubusercontent.com
    already exists (AWS allows just one per URL per account -- check
    IAM -> Identity providers first; a duplicate-create fails the apply).
  EOT
  type    = bool
  default = true
}

# GitHub's OIDC thumbprint. GitHub rotates the underlying cert but keeps
# this thumbprint value stable; AWS also validates the token itself, so this
# is not a meaningful security control -- it's just a required field.
locals {
  github_oidc_thumbprint = "6938fd4d98bab03faadb97b34396831e3780aea"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_repo != "" && var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [local.github_oidc_thumbprint]

  tags = local.common_tags
}

# Used instead of the resource above when create_github_oidc_provider = false,
# i.e. a provider already exists in this account (e.g. from another repo).
data "aws_iam_openid_connect_provider" "github" {
  count = var.github_repo != "" && !var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.github_repo == "" ? "" : (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

resource "aws_iam_role" "github_actions" {
  count = var.github_repo == "" ? 0 : 1
  name  = "${local.name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.github_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "github_actions_ecr_eks" {
  count = var.github_repo == "" ? 0 : 1
  name  = "ecr-push-and-eks-describe"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "EksDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = module.eks.cluster_arn
      }
    ]
  })
}

output "github_actions_role_arn" {
  value       = var.github_repo == "" ? "Set var.github_repo (or -var github_repo=org/repo) to create this role" : aws_iam_role.github_actions[0].arn
  description = "Put this in the AWS_ROLE_TO_ASSUME repo variable/secret for GitHub Actions"
}
