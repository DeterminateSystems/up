# Up

A Nix development environment project from Determinate Systems.

## Setup

Add the overlay:

```nix
{
  pkgs = import inputs.nixpkgs {
    overlays = [ inputs.up.overlays.default ];
  };
}
```

This provides the `lib.mkTaskRunner` and `lib.mkProcessTree` functions you'll see below.

The flake schemas are also helpful:

```text
{
  schemas = inputs.up.exportedSchemas // {
    # other schemas
  };
}
```

## Toolchains

**Toolchains** are configurable sets of tools that you can add to a dev shell.

```nix
{
  devShells = forEachSupportedSystem (
    { pkgs, system }:
    {
      default =
        let
          pythonToolchain = inputs.up.toolchains.${system}.python { uv = true; };
          rustToolchain = inputs.up.toolchains.${system}.rust { channel = "nightly"; };
        in
        pkgs.mkShell {
          packages = [
            pythonToolchain.packages
            rustToolchain.packages
          ];

          shellHook = ''
            ${pythonToolchain.shellHook}
          '';
        };
    }
  );
}
```

## Process trees

**Process trees** are [process-compose] configurations built with Nix.
Here's an example:

```nix
{
  processTrees = forEachSupportedSystem (
    { pkgs, system }:
    {
      postgres = pkgs.lib.mkProcessTree {
        description = "Run Postgres locally";

        packages = with pkgs; [
          (postgresql_18.withPackages (p: with p; [ pg_uuidv7 ]))
          redis
        ];

        # environment variables that are simple strings passed to process-compose
        staticEnvVars = {
          PGDATABASE = "testing";
          PGPORT = toString 5432;
        };

        # environment variables that become exports in the command script
        runtimeEnvVars = rec {
          PGDATA = "$PWD/.state/postgres";
          PGHOST = PGDATA;
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

              psql -c "CREATE EXTENSION IF NOT EXISTS pg_uuidv7;"
            '';
            depends_on.postgres.condition = "process_healthy";
          };
        };
      };
    }
  );
}
```

To run:

```shell
nix run ".#processTrees.<system>.postgres"
```

Notice that you can provide packages at the top level.
You can also provide packages only to a specific process:

```nix
{
  postgres-setup = {
    packages = [ pkgs.postgresql ];
    command = ''
      mkdir -p $PGDATA
      [[ -e "$PGDATA/PG_VERSION" ]] || initdb --no-locale --encoding=UTF8
    '';
  };
}
```

## Task runners

**Task runners** are generated CLI tools that enable you to run tasks.
Here's an example:

```nix
{
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
}
```

That generates a CLI tool for you called `work` that provides this help output:

```shell
work - Run linters and formatters

Available tasks:
  check-nix-formatting Check Nix formatting
  format-nix           Format Nix files
```

To run it:

```shell
nix run ".#taskRunners.<system>.default"
```

## Environment variable sets

There are two types of environment variable sets: **static** and **computed**.
Static sets are attribute sets of strings:

```nix
{
  staticEnvVars.postgres = {
    PGDATA = ".state/postgres";
    PGDATABASE = "testing";
    PGHOST = "127.0.0.1";
    PGPORT = toString 5432;
  };
}
```

Computed sets are system specific and may be based on things like packages in Nixpkgs:

```nix
computedEnvVars = forEachSupportedSystem (
  { pkgs, ... }:
  {
    postgres.PGSSLCERT = "${pkgs.postgresql}/share/postgresql/root.crt";
  }
);
```

[process-compose]: https://f1bonacc1.github.io/process-compose
