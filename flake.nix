{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nixpkgs-lib.follows = "nixpkgs";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs-lib";
    };
    opam-nix = {
      url = "github:debarchito/opam-nix";
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

          # setup toolchain and builders.
          rust-toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (crane.mkLib pkgs).overrideToolchain rust-toolchain;
          on = opam-nix.lib.${system};

          # setup base ocaml tooling.
          ocamlBasePackagesQuery = {
            ocaml-variants = "5.5.0+options,ocaml-option-flambda";
            ocaml-config = "*";
            miru = "*";
            miru-repl = "*";
          };
          ocamlDevPackagesQuery = {
            ocamlformat = "*";
            ocaml-lsp-server = "*";
          };

          baseOcamlScope = on.buildOpamProject' {
            repos = [ opam-repository ];
          } (lib.cleanSource ./.) (ocamlBasePackagesQuery // ocamlDevPackagesQuery);
          baseOcamlCompiler = baseOcamlScope.ocaml-compiler;

          # build the miru-machine static object, which depends on the base ocaml compiler
          # due to ocaml-interop.
          rustSrc = craneLib.cleanCargoSource ./.;
          miruMachineCommonArgs = {
            pname = "miru-machine";
            version = "0.1.0";
            cargoExtraArgs = "-p miru-machine";
            src = rustSrc;
            strictDeps = true;
            nativeBuildInputs = [ baseOcamlCompiler ];
          };
          miruMachineCargoArtifacts = craneLib.buildDepsOnly miruMachineCommonArgs;
          miru-machine = craneLib.buildPackage (
            miruMachineCommonArgs
            // {
              cargoArtifacts = miruMachineCargoArtifacts;
            }
          );

          # inject the miru-machine static object into miru. additionally, setup injection
          # env variables for conditional compilation on the dune side.
          ocamlScope = baseOcamlScope.overrideScope (
            _: prev: {
              inherit miru-machine;

              miru = prev.miru.overrideAttrs (oldAttrs: {
                propagatedBuildInputs = (oldAttrs.propagatedBuildInputs or [ ]) ++ [ miru-machine ];

                # when inside the Nix builder, it'll use the static object prepared by
                # crane instead of trying to build it itself.
                IS_NIX_BUILD_ENV = "true";
                CRANE_MIRU_MACHINE_DIR = "${miru-machine}";
              });
            }
          );

          # put the toolchains and development tools in one place.
          devPackages = [
            rust-toolchain
            ocamlScope.ocaml-compiler
          ]
          ++ builtins.attrValues (pkgs.lib.getAttrs (builtins.attrNames ocamlDevPackagesQuery) ocamlScope);
        in
        {
          packages = rec {
            inherit (ocamlScope)
              miru
              miru-machine
              miru-repl
              ;
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
            inherit miru-machine;

            miru-machine-clippy = craneLib.cargoClippy (
              miruMachineCommonArgs
              // {
                cargoArtifacts = miruMachineCargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            miru-machine-fmt = craneLib.cargoFmt { src = rustSrc; };

            miru-machine-audit = craneLib.cargoAudit {
              src = rustSrc;
              inherit advisory-db;
            };
          };

          overlayAttrs = {
            inherit (ocamlScope)
              miru
              miru-machine
              miru-repl
              ;
          };

          devShells.default = pkgs.mkShell {
            name = "miru-dev";

            inputsFrom = builtins.attrValues {
              inherit (ocamlScope)
                miru
                miru-machine
                miru-repl
                ;
            };
            nativeBuildInputs = devPackages;

            # Required for conditional compilation to work nice when using dune directly.
            IS_NIX_BUILD_ENV = "false";
          };
        };
    };
}
