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
            in
            pkgs.mkShellNoCC {
              packages = with pkgs; [
                self.taskRunners.${system}.default
                self.formatter.${system}

                phpToolchain.packages
                pythonToolchain.packages
                rustToolchain.packages
              ];
              shellHook = ''
                ${self.taskRunners.${system}.default.shellHook}
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

      toolchains = forEachSupportedSystem (
        { pkgs, system }:
        {
          go =
            {
              version ? null,
            }:
            {
              packages =
                if version == null then
                  pkgs.go
                else
                  pkgs.${"go_1_${builtins.replaceStrings [ "." ] [ "_" ] (toString version)}"};
            };

          js =
            {
              nodejs ? false,
              bun ? false,
              npm ? false,
              pnpm ? false,
            }:
            {
              packages = pkgs.symlinkJoin {
                name = "js-env";
                paths =
                  lib.optional nodejs pkgs.nodejs
                  ++ lib.optional bun pkgs.bun
                  ++ lib.optional npm pkgs.npm
                  ++ lib.optional pnpm pkgs.pnpm;
              };
            };

          php =
            {
              version ? "8.3",
              ini ? "",
              fpm ? {
                pools = { };
              },
            }:
            let
              phpPkg =
                pkgs.${"php${builtins.replaceStrings [ "." ] [ "" ] version}"}
                  or (throw "unknown php version: ${version}");

              fpmConf = pkgs.writeText "php-fpm.conf" (
                lib.concatStrings (
                  lib.mapAttrsToList (
                    poolName: pool:
                    ''
                      [${poolName}]
                    ''
                    + lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = ${v}\n") (pool.settings or { }))
                  ) (fpm.pools or { })
                )
              );

              shellHook = lib.optionalString (fpm.pools != { }) ''
                php-fpm -y ${fpmConf} -D
                trap "php-fpm -y ${fpmConf} -F -R 2>/dev/null" EXIT
              '';
            in
            {
              packages =
                if ini == "" then
                  phpPkg
                else
                  phpPkg.buildEnv {
                    extraConfig = ini;
                  };
              shellHook = lib.optionalString (fpm.pools != { }) ''
                php-fpm -y ${fpmConf} -D
                trap "php-fpm -y ${fpmConf} -F -R 2>/dev/null" EXIT
              '';
              env = { };
            };

          python =
            {
              version ? null,
              uv ? false,
              venv ? {
                enable = false;
                requirements = "";
              },
            }:
            let
              pythonPkg =
                if version == null then
                  pkgs.python3
                else
                  pkgs.${"python${builtins.replaceStrings [ "." ] [ "" ] version}"}
                    or (throw "unknown python version: ${version}");
            in
            {
              packages = pkgs.symlinkJoin {
                name = "python-env";
                paths = [ pythonPkg ] ++ lib.optional uv pkgs.uv;
              };

              shellHook = lib.optionalString (venv.enable or false) ''
                uv venv .venv
                ${lib.optionalString (venv.requirements or "" != "") ''
                  uv pip install ${venv.requirements}
                ''}
              '';
            };

          rust =
            {
              stable ? true,
              channel ? null,
              targets ? [ ],
              envSrcPath ? false,
            }:
            let
              fenixPkgs = inputs.fenix.packages.${system};

              rustToolchain =
                (
                  if channel != null then
                    {
                      "stable" = fenixPkgs.stable;
                      "nightly" = fenixPkgs.latest;
                      "beta" = fenixPkgs.beta;
                    }
                    .${channel} or (throw "unknown rust channel: ${channel}")
                  else if stable then
                    fenixPkgs.stable
                  else
                    fenixPkgs.latest
                ).toolchain;

              targetStdlibs = map (target: fenixPkgs.targets.${target}.stable.rust-std) targets;

              packages = fenixPkgs.combine ([ rustToolchain ] ++ targetStdlibs);
            in
            {
              env = lib.optionalAttrs envSrcPath {
                RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
              };

              inherit packages;
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
            Each toolchain returns `{ packages, shellHook }`.
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
