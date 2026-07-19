# Running the Jenkins pipeline

The `Jenkinsfile` at the repo root mirrors `.github/workflows/app-ci-cd.yml`
stage-for-stage (test → build & push → deploy), for teams standardized on
Jenkins instead of GitHub Actions.

## Job setup

1. Create a **Multibranch Pipeline** (or a Pipeline job with "Pipeline script
   from SCM") pointing at this repo, script path `Jenkinsfile`.
2. The agent running it needs: `python3`, `docker`, the `aws` CLI, and
   `kubectl` on `PATH`.
3. **Auth to AWS** — pick one:
   - Preferred: run the Jenkins agent on an EC2 instance / EKS pod with an
     IAM instance profile or IRSA role attached (same idea as the GitHub
     OIDC role in `terraform/github-oidc.tf` — no static keys).
   - Alternative: install the *AWS Credentials* plugin, store an access
     key/secret as a Jenkins credential, and wrap the shell steps in
     `withAWS(credentials: 'your-cred-id') { ... }`.
4. Either way, whatever identity Jenkins runs as needs the same permissions
   granted to the GitHub Actions role in `terraform/github-oidc.tf`
   (`ecr:*` push actions on the app repo, `eks:DescribeCluster`), plus an EKS
   **access entry** (see `terraform/eks.tf`'s `access_entries` block) so its
   IAM principal can actually run `kubectl` against the cluster.
5. Only the `main` branch runs the build/push/deploy stages (see the `when
   { branch 'main' }` guards) — other branches just run tests, matching the
   PR-vs-push split in the GitHub Actions version.

## What's different from the GitHub Actions version

- No native OIDC federation — auth relies on an attached IAM role or stored
  credentials instead of a per-run federated token.
- No separate "plan on PR" step for Terraform is included here; the
  `terraform.yml` GitHub workflow's plan/apply split would become two
  Jenkins jobs (or two stages gated on `env.CHANGE_ID` vs `branch main`) if
  you also want infra changes running through Jenkins.
