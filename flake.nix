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
              config = {
                allowBroken = true;
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
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              self.taskRunners.${system}.default
              self.formatter.${system}
            ];
            shellHook = ''
              ${self.taskRunners.${system}.default.shellHook}
            '';

            env = self.computedEnvVars.${system}.openssl;
          };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);

      lib = import ./nix/lib.nix { inherit lib; };

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
            description = "Run Postgres locally";

            packages = with pkgs; [
              (postgresql_18.withPackages (p: with p; [ pg_uuidv7 ]))
              openssl
              redis
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

              inherit (self.tasks.${system}) redis;
            };
          };
        }
      );

      taskRunners = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.lib.mkTaskRunner {
            name = "work";
            description = "Run linters and formatters";
            packages = with pkgs; [
              editorconfig-checker
              git
              nixfmt
            ];
            tasks = {
              check-nix-formatting = {
                description = "Check Nix formatting";
                command = "git ls-files -z '*.nix' | xargs -0 nixfmt check";
              };

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
