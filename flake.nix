{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nixpkgs-lib.follows = "nixpkgs";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      flake-parts,
      opam-nix,
      opam-repository,
      treefmt-nix,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        flake-parts.flakeModules.easyOverlay
        treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          lib,
          pkgs,
          system,
          ...
        }:
        let
          on = opam-nix.lib.${system};

          basePackagesQuery = {
            ocaml-variants = "5.4.1+options,ocaml-option-flambda";
            miru-core = "*";
            miru = "*";
          };

          devPackagesQuery = {
            ocamlformat = "*";
            ocaml-lsp-server = "*";
          };

          scope = on.buildOpamProject' { repos = [ opam-repository ]; } (lib.cleanSource ./.) (
            basePackagesQuery // devPackagesQuery
          );

          devPackages = builtins.attrValues (pkgs.lib.getAttrs (builtins.attrNames devPackagesQuery) scope);
        in
        {
          packages = rec {
            inherit (scope) miru-core miru;
            default = miru;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              ocamlformat = {
                enable = true;
                package = scope.ocamlformat // {
                  meta.mainProgram = "ocamlformat";
                };
              };
            };
          };

          overlayAttrs = {
            inherit (scope) miru;
            ocamlPackages = builtins.attrValues {
              inherit (scope) miru-core;
            };
          };

          devShells.default = pkgs.mkShell {
            name = "miru-dev";
            inputsFrom = builtins.attrValues {
              inherit (scope) miru-core miru;
            };
            nativeBuildInputs = devPackages;
          };
        };
    };
}
