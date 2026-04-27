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
}
