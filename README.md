# EKS + CI/CD + Monitoring Demo

An end-to-end example of the core DevOps/Cloud loop:

**Terraform provisions the infrastructure → GitHub Actions builds/tests/deploys
the app → Prometheus & Grafana watch it run.**

```
                     ┌─────────────────────────────────────────────┐
                     │                   AWS                        │
                     │  ┌───────────┐   ┌─────────────────────────┐│
  git push  ─────────┼─▶│   ECR     │   │         EKS             ││
     │                │  │ (images)  │──▶│  ┌────────────────┐    ││
     ▼                │  └───────────┘   │  │ sample-app ns  │    ││
┌──────────┐          │                  │  │ Deploy+HPA+Svc │    ││
│  GitHub  │          │                  │  └────────────────┘    ││
│ Actions  │──OIDC────┼──assume role────▶│  ┌────────────────┐    ││
│ (CI/CD)  │          │                  │  │ monitoring ns  │    ││
└──────────┘          │                  │  │ Prometheus +   │    ││
                     │                  │  │ Grafana        │    ││
                     │                  │  └────────────────┘    ││
                     │                  └─────────────────────────┘│
                     └─────────────────────────────────────────────┘
```

## What's in here

| Path | Purpose |
|---|---|
| `terraform/` | VPC, EKS cluster + managed node group, ECR repo, GitHub OIDC role, and the kube-prometheus-stack Helm release — all as code |
| `app/` | A tiny Flask service with `/health` and a Prometheus `/metrics` endpoint, plus its Dockerfile and tests |
| `k8s/` | Plain Kubernetes manifests: Namespace, Deployment, Service, HPA, ServiceMonitor |
| `.github/workflows/terraform.yml` | Plans infra changes on PRs, applies on merge to `main` |
| `.github/workflows/app-ci-cd.yml` | Tests the app, builds/pushes the image to ECR, deploys to EKS |
| `grafana/sample-app-dashboard.json` | A starter dashboard (import into Grafana) tracking request rate, p95 latency, error rate, and pod resource usage |
| `docs/bootstrap-backend.md` | One-time manual step to stand up remote Terraform state |

## Why it's built this way

- **No long-lived AWS keys in CI.** GitHub Actions authenticates via OIDC
  (`terraform/github-oidc.tf` creates the trust relationship + a scoped IAM
  role), not static access keys sitting in repo secrets.
- **Infra and app deploys are separate pipelines.** A code change shouldn't
  need to touch Terraform, and infra changes shouldn't require rebuilding the
  app — mirrors how most real platform teams split responsibilities.
- **Immutable, tagged images.** ECR is configured `IMMUTABLE`, images are
  tagged with the git SHA (not `latest`), so every deploy is traceable back to
  a commit.
- **Monitoring isn't bolted on after the fact.** The `ServiceMonitor` CRD ships
  alongside the app's own manifests, and the Helm release is provisioned by
  the same Terraform run as the cluster — metrics work from the first deploy.
- **Remote state + a manual apply gate.** `terraform.yml`'s `apply` job runs
  against a `production` GitHub Environment, which you can require reviewers
  on — infra changes get a real approval step, same as the app deploy.

## Prerequisites

- An AWS account + credentials locally (for the first bootstrap run)
- Terraform >= 1.7
- `kubectl`, `helm`, `aws` CLI
- A GitHub repo to push this into (for the Actions workflows to run)

## First-time setup

```bash
# 1. (optional but recommended) stand up remote state -- see docs/bootstrap-backend.md
# 2. Provision the cluster
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then fill in github_repo, region, etc.
terraform init
terraform apply

# 3. Point kubectl at it
aws eks update-kubeconfig --region <region> --name eks-demo-dev-cluster

# 4. Grab the CI role ARN from the apply output, put it in the repo as:
#    Settings -> Secrets and variables -> Actions -> New repository secret
#    Name: AWS_ROLE_TO_ASSUME   Value: <arn from output>

# 5. Re-apply once, passing the role, so it also gets kubectl access to the cluster:
terraform apply -var="ci_deploy_role_arn=<arn from step 4>"

# 6. Push to main / open a PR -- the GitHub Actions workflows take it from there
```

## Seeing it work

```bash
# App
kubectl get pods -n sample-app
kubectl port-forward -n sample-app svc/sample-app 8080:80
curl localhost:8080/           # sample payload
curl localhost:8080/metrics    # raw Prometheus metrics

# Grafana
kubectl get svc -n monitoring kube-prometheus-stack-grafana   # find the LoadBalancer address
# log in as admin / <grafana_admin_password from tfvars>
# Dashboards -> Import -> upload grafana/sample-app-dashboard.json
```

Generate some load so the dashboard has something to show:

```bash
for i in $(seq 1 200); do curl -s localhost:8080/ > /dev/null; done
```

## Using Jenkins instead of GitHub Actions

The pipeline logic is intentionally simple (test → build/push → deploy) and
maps directly onto a `Jenkinsfile` with three stages using the same
`aws ecr get-login-password`, `docker build/push`, and `kubectl apply` calls
from `app-ci-cd.yml`. The one thing you lose going this route is native OIDC
federation, so Jenkins would need an IAM instance role (if it runs on EC2/EKS
itself) or the AWS Jenkins plugin's credential provider instead of the
`aws-actions/configure-aws-credentials` OIDC step.

## Cost & teardown

This is sized to be cheap to run for a demo (single NAT gateway, `t3.medium`
nodes, 7-day metrics retention) but EKS + NAT + LoadBalancers are **not**
free. Tear it down when you're done:

```bash
cd terraform
terraform destroy
```

## Things a real production version would add

- Multiple environments (dev/staging/prod) via Terraform workspaces or
  separate state files, not just one `environment` variable
- Private-only API server endpoint + VPN/bastion access
- Ingress + TLS (e.g. AWS Load Balancer Controller + cert-manager) instead of
  a `LoadBalancer` Service on Grafana
- Alertmanager routing to Slack/PagerDuty, not just Prometheus collecting data
- Policy-as-code (OPA/Conftest) gating Terraform plans in CI
- Sealed Secrets / External Secrets Operator instead of tfvars-based passwords
