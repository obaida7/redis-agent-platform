resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.11"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  depends_on = [kubernetes_namespace.argocd]
}

# Apply the ArgoCD Application via kubectl after ArgoCD is running.
# kubectl_manifest requires a live cluster at plan time so we use
# a null_resource with local-exec instead.
resource "null_resource" "argocd_app" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<-EOF
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region us-east-1
      kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
      kubectl apply -f https://raw.githubusercontent.com/obaida7/redis-agent-platform/main/infrastructure/argocd/redis-app.yaml
    EOF
  }
}
