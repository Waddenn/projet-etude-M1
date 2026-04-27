{
  description = "NixOS K3s cluster on Proxmox for the DevOps M1 project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Manifests ArgoCD upstream, consommés par le module k8s-bootstrap.
    argo-cd = {
      url = "github:argoproj/argo-cd/v2.13.0";
      flake = false;
    };

    # Gestion des secrets encryptés in-repo via sops-nix.
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ nixpkgs, disko, argo-cd, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkNode = name: role: ip: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit argo-cd; };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./modules/disko-proxmox.nix
          ./modules/common.nix
          ./modules/secrets.nix
          ./modules/tailscale.nix
          ./modules/k3s-${role}.nix
          ./hosts/${name}.nix
          {
            networking.hostName = name;
            projet.k3s.nodeIp = ip;
          }
        ] ++ nixpkgs.lib.optional (role == "server") ./modules/k8s-bootstrap.nix;
      };

      # Pull du kubeconfig depuis cp-1 (utilisé via `just kubeconfig` ou direct).
      projet-kubeconfig = pkgs.writeShellApplication {
        name = "projet-kubeconfig";
        runtimeInputs = with pkgs; [ openssh coreutils gnused ];
        text = ''
          KEY="''${PROJET_K3S_KEY:-/tmp/projet-etude-k3s-ed25519}"
          OUT="''${1:-$HOME/.kube/projet-etude}"
          mkdir -p "$(dirname "$OUT")"
          ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            ops@192.168.1.61 'sudo cat /etc/rancher/k3s/k3s.yaml' \
            | sed 's|127\.0\.0\.1|192.168.1.61|' > "$OUT"
          chmod 600 "$OUT"
          echo "kubeconfig écrit dans $OUT"
          echo "export KUBECONFIG=$OUT"
        '';
      };
    in {
      nixosConfigurations = {
        k3s-cp-1 = mkNode "k3s-cp-1" "server" "192.168.1.61";
        k3s-worker-1 = mkNode "k3s-worker-1" "agent" "192.168.1.62";
        k3s-worker-2 = mkNode "k3s-worker-2" "agent" "192.168.1.63";
      };

      packages.${system} = {
        inherit projet-kubeconfig;
      };

      devShells.${system}.default = pkgs.mkShell {
        name = "projet-etude-devshell";
        packages = with pkgs; [
          just
          kubectl
          kubernetes-helm
          argocd
          k9s
          jq
          yq-go
          openssh
          sops
          age
          ssh-to-age
          projet-kubeconfig
        ];
        shellHook = ''
          echo "DevShell projet-etude prêt."
          echo "  just                    -> liste des recettes"
          echo "  projet-kubeconfig       -> récupère le kubeconfig depuis cp-1"
        '';
      };
    };
}
