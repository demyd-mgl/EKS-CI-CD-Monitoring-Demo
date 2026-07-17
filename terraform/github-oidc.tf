variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, as \"org/repo\" (e.g. \"myuser/devops-eks-demo\")"
  type        = string
  default     = ""
}

# Reuses an existing GitHub OIDC provider in the account if one was already
# created (common if you have other repos using this pattern); otherwise
# creates it. Comment this out and use only the `count = 0` version if you
# are certain none exists yet.
data "aws_iam_openid_connect_provider" "github" {
  count = var.github_repo == "" ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  count = var.github_repo == "" ? 0 : 1
  name  = "${local.name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github[0].arn
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
