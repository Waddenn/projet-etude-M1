{ ... }:

{
  # Control-plane K3s: API Kubernetes et point d'entrée kubectl.

  # Bootstrap GitOps : k3s applique les manifests ArgoCD à la première activation
  # puis ArgoCD prend la main et synchronise applications/ depuis le git.
  projet.argocd = {
    enable = true;
    repoUrl = "https://github.com/Waddenn/projet-etude-M1.git";
    targetRevision = "main";
  };

  # Exposition Tailnet des UIs déployées dans le cluster.
  # Les ports NodePort correspondants sont définis :
  #  - 30443 : argocd-server-ext     (modules/k8s-bootstrap.nix)
  #  - 30030 : kube-prometheus-stack-grafana (kubernetes/applications/monitoring/kube-prometheus-stack.yaml)
  projet.tailscaleServe = {
    enable = true;
    routes = {
      "443"  = "https+insecure://localhost:30443";  # ArgoCD
      "8443" = "http://localhost:30030";             # Grafana
    };
  };
}
