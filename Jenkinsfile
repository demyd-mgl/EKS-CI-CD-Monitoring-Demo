// Jenkinsfile — same three stages as .github/workflows/app-ci-cd.yml
// (test -> build & push to ECR -> deploy to EKS), for teams running Jenkins
// instead of GitHub Actions.
//
// Auth model: this assumes Jenkins runs on an EC2 host or in-cluster with an
// IAM role attached (instance profile / IRSA), so no static AWS keys are
// stored in Jenkins credentials either -- same "no long-lived keys" goal as
// the GitHub OIDC role in terraform/github-oidc.tf. If your Jenkins can't run
// with an attached role, swap the "AWS auth" step for the AWS Credentials
// plugin's withAWS(credentials: '...') wrapper instead.

pipeline {
    agent any

    parameters {
        string(name: 'AWS_REGION', defaultValue: 'eu-central-1', description: 'AWS region')
        string(name: 'ECR_REPOSITORY', defaultValue: 'eks-demo-dev-app', description: 'ECR repo name')
        string(name: 'CLUSTER_NAME', defaultValue: 'eks-demo-dev-cluster', description: 'EKS cluster name')
    }

    environment {
        IMAGE_TAG = "${env.GIT_COMMIT.take(7)}"
    }

    stages {
        stage('Test') {
            steps {
                dir('app') {
                    sh '''
                        python3 -m venv .venv
                        . .venv/bin/activate
                        pip install -r requirements-dev.txt
                        pytest -v
                    '''
                }
            }
        }

        stage('Build & push image') {
            when { branch 'main' }
            steps {
                script {
                    def account = sh(script: "aws sts get-caller-identity --query Account --output text", returnStdout: true).trim()
                    env.ECR_REGISTRY = "${account}.dkr.ecr.${params.AWS_REGION}.amazonaws.com"
                }
                sh '''
                    aws ecr get-login-password --region "$AWS_REGION" \
                      | docker login --username AWS --password-stdin "$ECR_REGISTRY"

                    IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
                    docker build -t "$IMAGE" app/
                    docker push "$IMAGE"
                '''
            }
        }

        stage('Deploy to EKS') {
            when { branch 'main' }
            steps {
                sh '''
                    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

                    IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
                    sed -i "s|IMAGE_PLACEHOLDER|$IMAGE|" k8s/deployment.yaml
                    sed -i "s|IMAGE_TAG_PLACEHOLDER|$IMAGE_TAG|" k8s/deployment.yaml

                    kubectl apply -f k8s/namespace.yaml
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl apply -f k8s/hpa.yaml
                    kubectl apply -f k8s/servicemonitor.yaml || echo "ServiceMonitor CRD not present yet -- apply the monitoring stack first"

                    kubectl rollout status deployment/sample-app -n sample-app --timeout=120s
                '''
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: 'app/**/test-results.xml'
            cleanWs()
        }
        failure {
            echo "Pipeline failed on ${env.BRANCH_NAME} @ ${env.GIT_COMMIT}"
            // hook a Slack/Teams notifier plugin here in a real setup
        }
    }
}
