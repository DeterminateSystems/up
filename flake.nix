{
  description = "up";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0";
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
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              self.taskRunners.${system}.common
              self.formatter.${system}
            ];
            shellHook = ''
              ${self.taskRunners.${system}.common.shellHook}
            '';
          };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);

      lib = import ./nix/lib.nix { inherit lib; };

      processTrees = forEachSupportedSystem (
        { pkgs, system }:
        {
          postgres = pkgs.lib.mkProcessTree {
            description = "Run Postgres locally";

            packages = with pkgs; [
              postgresql
            ];

            environment = {
              PGDATA = ".state/postgres";
              PGDATABASE = "testing";
              PGHOST = "127.0.0.1";
              PGPORT = "5432";
            };

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
          common = pkgs.lib.mkTaskRunner {
            name = "act";
            description = "Common repo tasks";
            tasks = {
              format = {
                command = ''
                  git ls-files -z "*.nix" | xargs -0 nixfmt

                  echo "Nix files properly formatted ❄️ ✅"
                '';
                packages = [ pkgs.nixfmt ];
                description = "Format Nix files";
              };

              editorconfig-check = {
                description = "Check conformance with your EditorConfig configuration";
                packages = [ pkgs.editorconfig-checker ];
              };

              inherit (self.tasks.${system}) redis;
            };
          };
        }
      );

      envVars = forEachSupportedSystem (
        { pkgs, ... }:
        {
          minio = {
            MINIO_ROOT_PASSWORD = "opensesame";
            MINIO_ROOT_USER = "justme";
          };

          postgres = {
            DATABASE_URL = "postgres://postgres@/mydb?host=$PWD/.state/postgres";
            OPENSSL_DIR = "${pkgs.openssl.dev}";
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

      overlays.default = final: prev: {
        lib =
          prev.lib
          // (import ./nix/lib.nix {
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
