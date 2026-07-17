variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "eks-demo"
}

variable "environment" {
  description = "Environment tag, e.g. dev/staging/prod"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "enable_monitoring_stack" {
  description = "Whether to install kube-prometheus-stack (Prometheus + Grafana) via Helm"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana. Override via TF_VAR_grafana_admin_password, never commit a real value."
  type        = string
  default     = "changeme-in-tfvars"
  sensitive   = true
}
