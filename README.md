# Up

A Nix development environment project from [Determinate Systems][detsys].

## Setup

Add the overlay:

```nix
{
  pkgs = import inputs.nixpkgs {
    overlays = [ inputs.up.overlays.default ];
  };
}
```

This provides the [`lib.mkTaskRunner`](#task-runners) and [`lib.mkProcessTree`](#process-trees) functions that you'll see below.

We also recommend using the exported [flake schemas](#schemas) if you create a flake that outputs one of Up's output types.

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

        # environment variables that become exports in the command script
        environment = rec {
          PGDATABASE = "testing";
          PGPORT = toString 5432;
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

### Process tree attributes

| Attribute            | Description                                                 | Default                |
| :------------------- | :---------------------------------------------------------- | :--------------------- |
| `name`               |                                                             |                        |
| `description`        |                                                             |                        |
| `environment`        |                                                             |                        |
| `package`            |                                                             | `pkgs.process-compose` |
| `packages`           |                                                             |                        |
| `log_level`          |                                                             |                        |
| `configFileName`     |                                                             | `process-compose.yaml` |
| `excludeShellChecks` |                                                             |                        |
| `processes`          | An attribute set of [processes](#process-attributes) to run |                        |

### Process attributes

| Attribute            | Description | Default |
| :------------------- | :---------- | :------ |
| `command`            |             |         |
| `working_dir`        |             |         |
| `watch`              |             |         |
| `environment`        |             |         |
| `packages`           |             |         |
| `description`        |             |         |
| `depends_on`         |             |         |
| `readiness_probe`    |             |         |
| `liveness_probe`     |             |         |
| `shutdown`           |             |         |
| `excludeShellChecks` |             |         |

### Watch process attributes

[watchexec]

| Attribute  | Description                                 | Default   |
| :--------- | :------------------------------------------ | :-------- |
| `paths`    | The filesystem paths to watch               | `[]`      |
| `action`   | `restart` (the default), `stop`, or `start` | `restart` |
| `ignore`   |                                             |           |
| `debounce` | The number of milliseconds to debounce      |           |

## Task runners

**Task runners** are generated CLI tools that enable you to run tasks.
[gum] is used to make the interface pretty and lively.

Here's how you can create a task runner:

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
╭───────────────────────────────────╮
│ work — Run linters and formatters │
╰───────────────────────────────────╯

Available tasks:

  check-nix-formatting    Check Nix formatting
  format-nix              Format Nix files
  all                     Run all tasks in dependency order

```

To run it:

```shell
nix run ".#taskRunners.<system>.default"
```

You can also add the runner to your development environment:

```nix
pkgs.mkShell {
  packages = [
    self.taskRunners.${system}.default

    # other packages
  ];
}
```

The generated `all` command runs all of your tasks and fails if any of those tasks don't return an exit code of 0.
And it runs those tasks as a [directed acyclic graph][dag] that's built when you specify `before` or `after` tasks (otherwise, it runs them in alphabetical order).
Here's an example:

```nix
{
  tasks = {
    earlier = {
      command = "echo 'Earlier'";
      before = [ "later" ];
    };

    later.command = "echo 'Later'";
  }:
}
```

Each task is converted into a Bash script using [`writeShellApplication`][writeshellapplication], which means that the `command` is run through [shellcheck].

### Task runner attributes

| Attribute     | Description                                                                                | Default                                            |
| :------------ | :----------------------------------------------------------------------------------------- | :------------------------------------------------- |
| `name`        | The name of the runnable executable for the runner                                         | THe key in the flake's `taskRunners` attribute set |
| `description` | The description of the runner that shows up in `nix flake show` output                     |                                                    |
| `environment` | Environment variables passed to all of the runner's tasks (supports variables like `$PWD`) |                                                    |
| `packages`    | A list of packages available to all the runner's tasks                                     |                                                    |
| `tasks`       | An attribute set of [tasks](#task-attributes) to run                                       |                                                    |

Here's an example:

```nix
pkgs.lib.mkTaskRunner {
  name = "rt";
  description = "Rust development tasks 🦀";
  environment.RUST_LOG = "trace";
  packages = with pkgs; [ cargo rustfmt ];
  tasks = { ... };
};
```

### Task attributes

| Attribute            | Description                                                                         | Default                                       |
| :------------------- | :---------------------------------------------------------------------------------- | :-------------------------------------------- |
| `name`               | The name for the task                                                               | The key in the runner's `tasks` attribute set |
| `description`        | The description of the task that shows up in the CLI and in `nix flake show` output |                                               |
| `command`            | The runnable command (verified by [shellcheck])                                     |                                               |
| `environment`        | Environment variables to pass to `command` (supports variables like `$PWD`)         |                                               |
| `packages`           | A list of packages to make available to the `command`                               | `[]`                                          |
| `before`             | The task before which the task needs to run                                         |                                               |
| `after`              | The task after which the task needs to run                                          |                                               |
| `requireArgs`        | Whether the command requires additional arguments                                   | `false`                                       |
| `confirm`            | Whether the command requires confirmation to proceed                                | `false`                                       |
| `raw`                | Whether you want the command to return raw shell output                             | `false`                                       |
| `aliases`            | Aliases for the command                                                             | `[]`                                          |
| `excludeShellChecks` | [shellcheck] rules to disable in the command                                        | `[]`                                          |

Here's an example:

```nix
{
  forrmat-rust = {
    command = "cargo fmt --all";
    packages = with pkgs; [ cargo rustfmt ];
    description = "Format all Rust files in the repo";
    before = [ "build" ];
    after = [ "lint" ];
    aliases = [ "f" ];
  };
}
```

## Environment variable sets

There are two types of environment variable sets: **static** and **computed**.
Static sets are attribute sets of plain strings:

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

## Schemas

We also recommend using the [flake schemas][flake-schemas] for added introspectability into your [`taskRunners`](#task-runners), [`processTrees`](#process-trees), and [environment variable](#environment-variable-sets) outputs:

```text
{
  schemas = inputs.up.exportedSchemas // {
    # other schemas
  };
}
```

[dag]: https://en.wikipedia.org/wiki/Directed_acyclic_graph
[detsys]: https://determinate.systems
[flake-schemas]: https://github.com/DeterminateSystems/flake-schemas
[gum]: https://github.com/charmbracelet/gum
[process-compose]: https://f1bonacc1.github.io/process-compose
[shellcheck]: https://shellcheck.net
[watchexec]: https://watchexec.github.io
[writeshellapplication]: https://ryantm.github.io/nixpkgs/builders/trivial-builders/#trivial-builder-writeShellApplication
