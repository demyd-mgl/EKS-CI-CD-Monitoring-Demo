resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring_stack ? 1 : 0

  metadata {
    name = "monitoring"
  }
}

# kube-prometheus-stack bundles Prometheus, Alertmanager, Grafana, and the
# CRDs (ServiceMonitor/PodMonitor) that the app's k8s/servicemonitor.yaml relies on.
resource "helm_release" "kube_prometheus_stack" {
  count = var.enable_monitoring_stack ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "62.3.1"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  # Demo-sized footprint. Bump storage/resources for anything long-lived.
  values = [
    yamlencode({
      grafana = {
        adminPassword = var.grafana_admin_password
        service = {
          type = "LoadBalancer" # swap for ClusterIP + Ingress in real prod
        }
      }
      prometheus = {
        prometheusSpec = {
          retention = "7d"
          resources = {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "500m", memory = "1Gi" }
          }
          # Scrape ServiceMonitors from any namespace, not just monitoring's own.
          serviceMonitorSelectorNilUsesHelmValues = false
        }
      }
      alertmanager = {
        enabled = true
      }
    })
  ]
}

output "grafana_hint" {
  value = var.enable_monitoring_stack ? "Grafana installed in the 'monitoring' namespace. Get its URL with: kubectl get svc -n monitoring kube-prometheus-stack-grafana" : "Monitoring stack disabled (enable_monitoring_stack = false)"
}
