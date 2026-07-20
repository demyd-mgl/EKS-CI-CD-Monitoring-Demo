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

# GitHub's OIDC intermediate CA thumbprints. AWS actually validates the token
# itself (audience + issuer + signature), so this thumbprint is a required
# field rather than a meaningful security control -- but it still has to be
# a syntactically valid 40-char SHA-1 hex digest, and GitHub's cert is
# cross-signed by two possible intermediate CAs, so both are listed here per
# GitHub's own guidance (see https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/).
locals {
  github_oidc_thumbprints = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_repo != "" && var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = local.github_oidc_thumbprints

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

locals {
  github_owner = element(split("/", var.github_repo), 0)
  github_repo_name = element(split("/", var.github_repo), 1)
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
          # Matches both subject claim formats GitHub issues:
          #  - legacy:   repo:OWNER/REPO:*
          #  - immutable (default for repos created after 2026-07-15, or
          #    opted into on older repos): repo:OWNER@ownerId/REPO@repoId:*
          # See https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:*",
            "repo:${local.github_owner}@*/${local.github_repo_name}@*:*",
          ]
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
      },
      {
        # The terraform-aws-modules/eks module resolves the calling
        # identity's underlying role (via data.aws_iam_session_context)
        # whenever enable_cluster_creator_admin_permissions = true, which
        # requires this role to be able to read its own IAM role.
        Sid      = "IamGetOwnRole"
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = aws_iam_role.github_actions[0].arn
      }
    ]
  })
}

output "github_actions_role_arn" {
  value       = var.github_repo == "" ? "Set var.github_repo (or -var github_repo=org/repo) to create this role" : aws_iam_role.github_actions[0].arn
  description = "Put this in the AWS_ROLE_TO_ASSUME repo variable/secret for GitHub Actions"
}

# The narrower policy above is enough for the app-deploy workflow (push to
# ECR, describe the cluster). But terraform.yml's apply job runs a full
# `terraform apply` against this whole stack -- VPC, security groups, IAM
# roles, EKS, ELB, KMS, autoscaling, etc. -- via the eks/vpc modules'
# transitive resources. Hand-crafting least-privilege IAM for that entire
# graph isn't practical for a personal/demo account, so this role gets broad
# admin permissions instead, and the real security boundary is:
#   1. the trust policy above (only this exact repo can assume the role)
#   2. the manual, typed-confirmation apply gate in .github/workflows/terraform.yml
# For a real production setup, replace this with a scoped policy covering
# only the specific ec2/iam/eks/elb/kms actions Terraform actually needs.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  count      = var.github_repo == "" ? 0 : 1
  role       = aws_iam_role.github_actions[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
