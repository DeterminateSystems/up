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

              pythonToolchain = toolchains.python {
                uv = true;
              };

              rustToolchain = toolchains.rust {
                channel = "stable";
                envSrcPath = true;
              };

              phpToolchain = toolchains.php { };

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

                self.taskRunners.${system}.fmt

                phpToolchain.packages
                pythonToolchain.packages
                rustToolchain.packages
                terraformToolchain.packages
              ];

              shellHook = ''
                ${pythonToolchain.shellHook}
                ${phpToolchain.shellHook}
              '';
              env = rustToolchain.env // self.envVars.postgres;
            };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);

      lib = import ./lib { inherit lib; };

      processTrees = forEachSupportedSystem (
        { pkgs, system }:
        {
          postgres = pkgs.lib.mkProcessTree {
            name = "postgres-process-tree";
            description = "Run Postgres locally";

            packages = with pkgs; [
              (postgresql_18.withPackages (p: with p; [ pg_uuidv7 ]))
              redis
            ];

            environment = self.envVars.postgres;

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

              inherit (self.tasks.${system}) redis;
            };
          };
        }
      );

      taskRunners = forEachSupportedSystem (
        { pkgs, system }:
        {
          fmt = pkgs.lib.mkTaskRunner {
            name = "fmt";
            description = "Run formatters";
            packages = with pkgs; [
              git
              nixfmt
            ];
            tasks = {
              format-nix = {
                description = "Format Nix files";
                command = "git ls-files -z '*.nix' | xargs -0 nixfmt";
              };
            };
          };
        }
      );

      tasks = forEachSupportedSystem (
        { pkgs, ... }:
        {
          redis = {
            description = "Run the Redis server";
            packages = [ pkgs.redis ];
            command = "redis-server";
          };

          format-sql = {
            description = "Format SQL files";
            packages = [ pkgs.sqlfluff ];
            command = ''
              git ls-files -z '*.sql' | xargs sqlfluff format
            '';
          };

          format-nix = {
            description = "Format all Nix files in the sourcetree";
            command = "git ls-files -z '*.nix' | xargs -0 nixfmt";
            packages = [ pkgs.nixfmt ];
          };
        }
      );

      toolchains = forEachSupportedSystem (
        { pkgs, system }:
        {
          go = import ./toolchains/go { inherit pkgs; };

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

      envVars.postgres = {
        PGDATA = ".state/postgres";
        PGDATABASE = "testing";
        PGHOST = "127.0.0.1";
        PGPORT = "5432";
      };

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
      // {
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

        envVars = {
          version = 1;
          doc = ''
            The `envVars` output provides sets of environment variables
            that can be sourced into shells or consumed by other tools.
          '';
          inventory =
            output:
            let
              isEnv = v: builtins.isAttrs v && builtins.all (s: builtins.isString s) (builtins.attrValues v);
              isPerSystem = builtins.all (v: builtins.isAttrs v && !isEnv v) (builtins.attrValues output);
            in
            inputs.flake-schemas.lib.mkChildren (
              if isPerSystem then
                builtins.mapAttrs (system: envs: {
                  forSystems = [ system ];
                  children = builtins.mapAttrs (_name: env: {
                    forSystems = [ system ];
                    evalChecks.isAttrs = builtins.isAttrs env;
                    evalChecks.allStrings = isEnv env;
                    what = "environment variable set";
                  }) envs;
                }) output
              else
                builtins.mapAttrs (_name: env: {
                  evalChecks.isAttrs = builtins.isAttrs env;
                  evalChecks.allStrings = isEnv env;
                  what = "environment variables set";
                }) output
            );
        };

        tasks = {
          version = 1;
          doc = ''
            The `tasks` output provides one-shot runnable commands such as database migrations, seed scripts, and build steps.
          '';
          roles.nix-run = { };
          appendSystem = true;
          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: tasks: {
                forSystems = [ system ];
                children = builtins.mapAttrs (taskName: task: {
                  forSystems = [ system ];
                  evalChecks = {
                    hasCommand = task ? command || task ? packages;
                    isAttrs = builtins.isAttrs task;
                  };
                  what = task.description or "task";
                }) tasks;
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
