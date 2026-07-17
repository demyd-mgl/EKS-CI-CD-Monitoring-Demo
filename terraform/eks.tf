module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "${local.name}-cluster"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true # demo convenience; restrict CIDRs / go private for real prod

  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns        = {}
    kube-proxy     = {}
    vpc-cni        = {}
    metrics-server = {} # required for the HPA in k8s/hpa.yaml to have CPU metrics to scale on
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      capacity_type  = "ON_DEMAND"
    }
  }

  # Lets the GitHub Actions deploy job (assuming an IAM role via OIDC) run
  # kubectl/helm against the cluster without a static kubeconfig lying around.
  access_entries = var.ci_deploy_role_arn == "" ? {} : {
    ci = {
      principal_arn = var.ci_deploy_role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.common_tags
}

variable "ci_deploy_role_arn" {
  description = "IAM role ARN assumed by GitHub Actions (via OIDC) that should get kubectl access to the cluster. Leave empty until the role exists, then re-apply."
  type        = string
  default     = ""
}
