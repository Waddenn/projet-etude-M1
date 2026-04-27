{ config, lib, pkgs, argo-cd, ... }:

let
  cfg = config.projet.argocd;
  manifestsDir = "/var/lib/rancher/k3s/server/manifests";

  # Namespace ArgoCD : doit exister avant l'apply de install.yaml,
  # d'où le préfixe lex `00-` pour passer en premier.
  argocdNamespace = pkgs.writeText "00-argocd-namespace.yaml" ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: argocd
  '';

  # Manifests upstream ArgoCD, pinés via le flake input `argo-cd`.
  # On injecte `metadata.namespace: argocd` sur les ressources namespaced
  # (le manifest upstream suppose `kubectl apply -n argocd ...`, ce que k3s
  # ne fait pas en lisant le dossier `manifests/`).
  argocdInstall = pkgs.runCommand "argocd-install-namespaced.yaml" {
    nativeBuildInputs = [ pkgs.yq-go ];
  } ''
    yq eval-all '
      with(
        select(.kind | test("^(ClusterRole|ClusterRoleBinding|CustomResourceDefinition|Namespace)$") | not);
        .metadata.namespace = "argocd"
      )
    ' ${argo-cd}/manifests/install.yaml > $out
  '';

  # Service NodePort additionnel pour exposer l'UI ArgoCD sur un port stable
  # de l'hôte (utilisé par tailscale serve). Ne touche pas au svc argocd-server
  # original (ClusterIP) qui reste géré par le manifest k3s.
  argocdServerNodePort = pkgs.writeText "20-argocd-server-nodeport.yaml" ''
    apiVersion: v1
    kind: Service
    metadata:
      name: argocd-server-ext
      namespace: argocd
      labels:
        app.kubernetes.io/component: server
        app.kubernetes.io/name: argocd-server
        app.kubernetes.io/part-of: argocd
    spec:
      type: NodePort
      selector:
        app.kubernetes.io/name: argocd-server
      ports:
        - name: https
          port: 443
          protocol: TCP
          targetPort: 8080
          nodePort: 30443
        - name: http
          port: 80
          protocol: TCP
          targetPort: 8080
          nodePort: 30080
  '';

  # Root Application "app of apps" : ArgoCD scanne le dossier git puis
  # synchronise tout ce qu'il y trouve (les Applications enfants).
  rootApp = pkgs.writeText "99-argocd-root-app.yaml" ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: ${cfg.repoUrl}
        targetRevision: ${cfg.targetRevision}
        path: ${cfg.appsPath}
        directory:
          recurse: true
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true
  '';
in
{
  options.projet.argocd = {
    enable = lib.mkEnableOption "Auto-bootstrap ArgoCD via les manifests k3s";

    repoUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://github.com/USER/projet-etude.git";
      description = ''
        URL du repo git contenant les Applications ArgoCD à synchroniser.
        Doit être accessible publiquement, ou disposer d'un repository
        secret ArgoCD configuré séparément.
      '';
    };

    targetRevision = lib.mkOption {
      type = lib.types.str;
      default = "HEAD";
      description = "Branche / tag / commit suivi par la root Application.";
    };

    appsPath = lib.mkOption {
      type = lib.types.str;
      default = "kubernetes/applications";
      description = "Chemin dans le repo où vivent les Applications enfants.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Le dossier doit exister avant que k3s ou tmpfiles n'y déposent quoi que ce soit.
    systemd.tmpfiles.rules = [
      "d ${manifestsDir} 0700 root root - -"
    ];

    # Symlinks vers le nix store : le contenu suit toute mise à jour de la config
    # (changement de repoUrl, bump du tag argocd, etc.) au prochain rebuild.
    systemd.tmpfiles.settings."10-projet-argocd" = {
      "${manifestsDir}/00-argocd-namespace.yaml"."L+".argument = toString argocdNamespace;
      "${manifestsDir}/10-argocd-install.yaml"."L+".argument = toString argocdInstall;
      "${manifestsDir}/20-argocd-server-nodeport.yaml"."L+".argument = toString argocdServerNodePort;
      "${manifestsDir}/99-argocd-root-app.yaml"."L+".argument = toString rootApp;
    };
  };
}
