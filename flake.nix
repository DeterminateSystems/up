{
  description = "up";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0";
    fenix = {
      url = "https://flakehub.com/f/nix-community/fenix/0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    let
      inherit (inputs.nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
              };
              overlays = [ self.overlays.default ];
            };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default =
            let
              toolchains = self.toolchains.${system};

              goToolchain = toolchains.go {
                version = "1.26";
                gofmt = true;
                gotools = true;
              };

              pythonToolchain = toolchains.python {
                uv = true;
              };

              rustToolchain = toolchains.rust {
                channel = "stable";
                targets = [ ];
                envSrcPath = true;
              };

              phpToolchain = toolchains.php {
                version = "8.4";
              };

              terraformToolchain = toolchains.terraform {
                plugins = [
                  "hashicorp_aws"
                  "hashicorp_google"
                  "hashicorp_kubernetes"
                ];
              };
            in
            pkgs.mkShellNoCC {
              packages = with pkgs; [
                self.formatter.${system}

                # Task runners
                self.taskRunners.${system}.fmt

                # Language toolchains
                goToolchain.packages
                phpToolchain.packages
                pythonToolchain.packages
                rustToolchain.packages
                terraformToolchain.packages

                # Process trees
                self.processTrees.${system}.postgres
              ];

              shellHook = ''
                ${pythonToolchain.shellHook}
                ${phpToolchain.shellHook}
              '';
              env = rustToolchain.env // self.computedEnvVars.${system}.openssl // terraformToolchain.env;
            };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);

      lib = import ./lib { inherit lib; };

      staticEnvVars.postgres = {
        PGDATA = ".state/postgres";
        PGDATABASE = "testing";
        PGHOST = "127.0.0.1";
        PGPORT = "5432";
      };

      computedEnvVars = forEachSupportedSystem (
        { pkgs, system }:
        {
          openssl = {
            OPENSSL_DIR = "${pkgs.openssl.dev}";
            OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
            OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
          };
        }
      );

      processTrees = forEachSupportedSystem (
        { pkgs, system }:
        {
          postgres = pkgs.lib.mkProcessTree {
            name = "run-pg";
            description = "Run Postgres locally";

            packages = with pkgs; [
              (postgresql_18.withPackages (p: with p; [ pg_uuidv7 ]))
            ];

            environment = self.staticEnvVars.postgres // self.computedEnvVars.${system}.openssl;

            processes = {
              postgres-setup = {
                command = ''
                  mkdir -p $PGDATA
                  [[ -e "$PGDATA/PG_VERSION" ]] || initdb --no-locale --encoding=UTF8
                '';
              };

              postgres = {
                command = "postgres";
                depends_on.postgres-setup.condition = "process_completed_successfully";
                readiness_probe = {
                  exec.command = "pg_isready";
                  initial_delay_seconds = 1;
                  period_seconds = 2;
                  failure_threshold = 100;
                };
              };

              postgres-post-startup = {
                command = ''
                  createdb $PGDATABASE || true

                  psql -c "CREATE EXTENSION IF NOT EXISTS pg_uuidv7;"
                '';
                depends_on.postgres.condition = "process_healthy";
              };
            };
          };
        }
      );

      taskRunners = forEachSupportedSystem (
        { pkgs, system }:
        {
          fmt = pkgs.lib.mkTaskRunner {
            name = "fmt";
            description = "Run various formatters";
            packages = with pkgs; [
              nixfmt
              sqlfluff
            ];
            tasks = {
              format-nix = {
                description = "Format Nix files using nixfmt";
                command = ''
                  echo "Formatting Nix files 🤖"
                  git ls-files -z '*.nix' | xargs -0 nixfmt
                  echo "Successfully formatted Nix files ✅"
                '';
              };

              format-sql = {
                description = "Format SQL files using sqlfluff";
                command = ''
                  echo "Formatting SQL files 🤖"
                  sqlfluff format
                  echo "Successfully formatted SQL files ✅"
                '';
              };
            };
          };
        }
      );

      toolchains = forEachSupportedSystem (
        { pkgs, system }:
        {
          go = import ./toolchains/go { inherit lib pkgs; };

          terraform = import ./toolchains/terraform { inherit pkgs; };

          js = import ./toolchains/js { inherit lib pkgs; };

          php = import ./toolchains/php { inherit lib pkgs; };

          python = import ./toolchains/python {
            inherit lib pkgs;
          };

          rust = import ./toolchains/rust {
            inherit (inputs) fenix;
            inherit lib system;
          };
        }
      );

      overlays.default = final: prev: {
        lib =
          prev.lib
          // (import ./lib {
            inherit (prev) lib;
            pkgs = prev;
          });
      };

      schemas = {
        inherit (inputs.flake-schemas.schemas)
          devShells
          formatter
          overlays
          schemas
          ;
      }
      // self.exportedSchemas;

      exportedSchemas = {
        exportedSchemas = {
          version = 1;
          doc = ''
            The `exportedSchemas` flake output is used to define flake schemas that you
            intend for other flakes to use.
          '';

          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (schemaName: schemaDef: {
                shortDescription = "A schema checker for the `${schemaName}` flake output";
                evalChecks.isValidSchema =
                  schemaDef.version or 0 == 1
                  && schemaDef ? doc
                  && builtins.isString (schemaDef.doc)
                  && schemaDef ? inventory
                  && builtins.isFunction (schemaDef.inventory);
                what = "flake schema";
              }) output
            );
        };

        taskRunners = {
          version = 1;
          doc = ''
            The `taskRunners` output provides a CLI task runner with shell completions.
          '';
          appendSystem = true;
          defaultAttrPath = [ "default" ];
          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: runners: {
                forSystems = [ system ];
                children = builtins.mapAttrs (_name: runner: {
                  forSystems = [ system ];
                  evalChecks.isDerivation = lib.isDerivation runner;
                  what = runner.description or "task runner";
                }) runners;
              }) output
            );
        };

        toolchains = {
          version = 1;
          doc = ''
            The `toolchains` output provides language toolchain builder functions.
            Each toolchain returns `{ packages, env, shellHook }`.
          '';
          appendSystem = true;
          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: toolchains: {
                forSystems = [ system ];
                children = builtins.mapAttrs (_name: toolchain: {
                  forSystems = [ system ];
                  evalChecks.isFunction = builtins.isFunction toolchain;
                  what = "language toolchain builder";
                }) toolchains;
              }) output
            );
        };

        staticEnvVars = {
          version = 1;
          doc = ''
            The `staticEnvVars` output provides sets of environment variables
            that can be sourced into shells or consumed by other tools.
          '';
          inventory =
            output:
            let
              isEnv = v: builtins.isAttrs v && builtins.all (s: builtins.isString s) (builtins.attrValues v);
            in
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (_name: env: {
                evalChecks.isAttrs = builtins.isAttrs env;
                evalChecks.allStrings = isEnv env;
                what = "environment variables set";
              }) output
            );
        };

        computedEnvVars = {
          version = 1;
          doc = ''
            The `computedEnvVars` output provides sets of environment variables
            that can be sourced into shells or consumed by other tools. Unlike `staticEnvVars`, these
            sets are system specific and involve some kind of computation (like using packages from Nixpkgs).
          '';
          appendSystem = true;
          inventory =
            output:
            let
              isEnv = v: builtins.isAttrs v && builtins.all (s: builtins.isString s) (builtins.attrValues v);
            in
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: envs: {
                forSystems = [ system ];
                children = builtins.mapAttrs (_name: env: {
                  forSystems = [ system ];
                  evalChecks.isAttrs = builtins.isAttrs env;
                  evalChecks.allStrings = isEnv env;
                  what = "computed environment variable set";
                }) envs;
              }) output
            );
        };

        processTrees = {
          version = 1;
          doc = ''
            The `processTrees` output provides process-compose configurations that you can run using `nix run`.
          '';
          roles.nix-run = { };
          appendSystem = true;
          defaultAttrPath = [ "default" ];
          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: trees: {
                forSystems = [ system ];
                children = builtins.mapAttrs (_name: tree: {
                  forSystems = [ system ];
                  evalChecks.isDerivation = lib.isDerivation tree;
                  what = tree.description or "process tree";
                }) trees;
              }) output
            );
        };
      };
    };
}
