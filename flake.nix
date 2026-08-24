{
  description = "Description for the project";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs-stable, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import a flake module
        # 1. Add foo to inputs
        # 2. Add foo as a parameter to the outputs function
        # 3. Add here: foo.flakeModule

      ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem =
        {
          pkgs,
          system,
          ...
        }:
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.
          _module.args.pkgs = import inputs.nixpkgs {
            inherit pkgs system;
            config.allowUnfree = true;
          };

          # Dev shells
          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # Formatter for alloy config file
              grafana-alloy
              go-task
              fluxcd
              fluxcd-operator
              yq-go
              gitleaks
              pre-commit
              talosctl
              # Sourced from nixos-26.05 stable, not nixos-unstable.
              # nixos-unstable's minikube fetches its source by tag, so
              # `src.rev` resolves to `refs/tags/v1.38.1`. That string
              # contains forward slashes, which Kubernetes rejects as a node
              # label value, so multi-node clusters fail at the first worker
              # join with `GUEST_START: invalid label value:
              # minikube.k8s.io/commit=refs/tags/v1.38.1`.
              # nixos-26.05 fetches by rev instead, so `src.rev` is `v1.38.1`
              # (a valid label). Both channels ship minikube 1.38.1.
              # See DECISION.md for details.
              (nixpkgs-stable.legacyPackages.${system}.minikube.override { withQemu = true; })
              awscli2
              infisical
            ];

            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
              pkgs.libvirt
            ];

            shellHook = ''
              export AWS_PROFILE=rook-dev
              export AWS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt
            '';
          };
        };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.
      };
    };
}
