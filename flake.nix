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
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      opam-nix,
      opam-repository,
      crane,
      rust-overlay,
      advisory-db,
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
        { lib, system, ... }:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;
          rustSrc = craneLib.cleanCargoSource ./.;

          on = opam-nix.lib.${system};

          ocamlBasePackagesQuery = {
            ocaml-variants = "5.4.1+options,ocaml-option-flambda";
            miru-core = "*";
            miru = "*";
            miru-repl = "*";
          };
          ocamlDevPackagesQuery = {
            ocamlformat = "*";
            ocaml-lsp-server = "*";
          };

          ocamlBaseScope = on.buildOpamProject' {
            repos = [ opam-repository ];
          } (lib.cleanSource ./.) (ocamlBasePackagesQuery // ocamlDevPackagesQuery);

          ocamlCompiler = ocamlBaseScope.ocaml-compiler;

          miruRtlCommonArgs = {
            pname = "miru-rtl";
            version = "0.1.0";
            cargoExtraArgs = "-p miru-rtl";
            src = rustSrc;
            strictDeps = true;
            nativeBuildInputs = [ ocamlCompiler ];
          };
          miruRtlCargoArtifacts = craneLib.buildDepsOnly miruRtlCommonArgs;

          miru-rtl = craneLib.buildPackage (
            miruRtlCommonArgs
            // {
              cargoArtifacts = miruRtlCargoArtifacts;
            }
          );

          ocamlScope = ocamlBaseScope.overrideScope (
            _: prev: {
              inherit miru-rtl;

              miru = prev.miru.overrideAttrs (oldAttrs: {
                propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [ miru-rtl ];

                IS_NIX_BUILD_ENV = "true";
                MIRU_RTL_DIR = "${miru-rtl}";
              });
            }
          );

          devPackages = [
            rust-toolchain
            ocamlCompiler
          ]
          ++ builtins.attrValues (pkgs.lib.getAttrs (builtins.attrNames ocamlDevPackagesQuery) ocamlScope);
        in
        {
          packages = rec {
            inherit miru-rtl;
            inherit (ocamlScope) miru miru-repl;
            default = miru;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              rustfmt = {
                enable = true;
                package = rust-toolchain;
              };
              ocamlformat = {
                enable = true;
                package = ocamlScope.ocamlformat // {
                  meta.mainProgram = "ocamlformat";
                };
              };
            };
          };

          checks = {
            inherit miru-rtl;

            miru-rtl-clippy = craneLib.cargoClippy (
              miruRtlCommonArgs
              // {
                cargoArtifacts = miruRtlCargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            miru-rtl-fmt = craneLib.cargoFmt { src = rustSrc; };

            miru-rtl-audit = craneLib.cargoAudit {
              src = rustSrc;
              inherit advisory-db;
            };
          };

          overlayAttrs = {
            inherit miru-rtl;
            inherit (ocamlScope) miru miru-repl;
          };

          devShells.default = pkgs.mkShell {
            name = "miru-dev";

            inputsFrom = builtins.attrValues {
              inherit miru-rtl;
              inherit (ocamlScope) miru-core miru miru-repl;
            };
            nativeBuildInputs = devPackages;

            IS_NIX_BUILD_ENV = "false";
          };
        };
    };
}
