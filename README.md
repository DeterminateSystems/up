# Up

A set of Nix development environment helpers from [Determinate Systems][detsys].

## Setup

To use the functions in this flake, add the overlay:

```nix
{
  pkgs = import inputs.nixpkgs {
    overlays = [ inputs.up.overlays.default ];
  };
}
```

This provides the [`lib.mkTaskRunner`](#task-runners), [`lib.mkProcessTree`](#process-trees), and other functions that you'll see below.

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

| Attribute            | Description                                                                     | Default                                             |
| :------------------- | :------------------------------------------------------------------------------ | :-------------------------------------------------- |
| `name`               | The name of the runnable executable for the process tree                        | The key in the flake's `processTrees` attribute set |
| `processes`          | An attribute set of [processes](#process-attributes) to run                     |                                                     |
| `environment`        | Environment variables to pass to all processes (supports variables like `$PWD`) | `{ }`                                               |
| `package`            | The [process-compose] package                                                   | `pkgs.process-compose`                              |
| `packages`           | A list of packages to make available to all processes                           |                                                     |
| `log_level`          | `info` (the default), `trace`, `debug`, `warn`, `error`, `fatal`, or `panic`    | `info`                                              |
| `configFileName`     | The name of the generated configuration file                                    | `process-compose.yaml`                              |
| `excludeShellChecks` | [shellcheck] rules to disable in all processes                                  | `[ ]`                                               |

### Process attributes

| Attribute            | Description                                                                   | Default |
| :------------------- | :---------------------------------------------------------------------------- | :------ |
| `command`            | The runnable command (verified by [shellcheck])                               |         |
| `working_dir`        | The working directory for the process                                         |         |
| `watch`              | Configuration for a [file watcher](#watch-process-attributes)                 |         |
| `environment`        | Environment variables to pass to the process (supports variables like `$PWD`) | `{ }`   |
| `packages`           | A list of packages to make available to the process's `command`               | `[ ]`   |
| `description`        | The description of the process that shows up in `nix flake show` output       |         |
| `depends_on`         | The processes that the process [depends on][depends-on]                       | `{ }`   |
| `readiness_probe`    | A [readiness probe][readiness-probe] for the process                          |         |
| `liveness_probe`     | A [liveness probe][liveness-probe] for the process                            |         |
| `shutdown`           | A [shutdown] directive for the process                                        |         |
| `excludeShellChecks` | [shellcheck] rules to disable in the process's `command`                      | `[ ]`   |

### Watch process attributes

Your process tree can have [watchexec]-driven processes that are restarted when files at specified paths change.

| Attribute  | Description                                 | Default   |
| :--------- | :------------------------------------------ | :-------- |
| `paths`    | The filesystem paths to watch               | `[ ]`     |
| `action`   | `restart` (the default), `stop`, or `start` | `restart` |
| `ignore`   | The filesystem paths to ignore              | `[ ]`     |
| `debounce` | The number of milliseconds to debounce      |           |

## Task runners

**Task runners** are generated CLI tools that enable you to run tasks.
We use the lovely [gum] to make that generated CLI pretty and lively.

Here's how you can create a task runner in your flake:

```nix
{
  taskRunners = forEachSupportedSystem (
    { pkgs, system }:
    {
      default = pkgs.lib.mkTaskRunner {
        name = "work";
        description = "Run linters and formatters";
        packages = with pkgs; [
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
            after = [ "check-nix-formatting" ];
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
  };
}
```

The function converts each task into a proper Bash script using [`writeShellApplication`][writeshellapplication], which means that the `command` is linted by [shellcheck].

### Task runner attributes

| Attribute     | Description                                                                                | Default                                            |
| :------------ | :----------------------------------------------------------------------------------------- | :------------------------------------------------- |
| `name`        | The name of the runnable executable for the runner                                         | The key in the flake's `taskRunners` attribute set |
| `description` | The description of the runner that shows up in `nix flake show` output                     | `task runner`                                      |
| `environment` | Environment variables passed to all of the runner's tasks (supports variables like `$PWD`) | `{ }`                                              |
| `packages`    | A list of packages available to all the runner's tasks                                     |                                                    |
| `tasks`       | An attribute set of [tasks](#task-attributes) to run                                       |                                                    |

Here's an example:

```nix
pkgs.lib.mkTaskRunner {
  name = "rt";
  description = "Rust development tasks 🦀";
  environment.RUST_LOG = "trace";
  packages = with pkgs; [
    cargo
    rustfmt
  ];
  tasks = {
    forrmat-rust = { ... };
  };
}
```

### Task attributes

| Attribute            | Description                                                                         | Default                                       |
| :------------------- | :---------------------------------------------------------------------------------- | :-------------------------------------------- |
| `name`               | The name for the task                                                               | The key in the runner's `tasks` attribute set |
| `description`        | The description of the task that shows up in the CLI and in `nix flake show` output | `runnable task`                               |
| `command`            | The runnable command (verified by [shellcheck])                                     |                                               |
| `environment`        | Environment variables to pass to `command` (supports variables like `$PWD`)         | `{ }`                                         |
| `packages`           | A list of packages to make available to the `command`                               | `[ ]`                                         |
| `before`             | The tasks before which the task needs to run                                        | `[ ]`                                         |
| `after`              | The tasks after which the task needs to run                                         | `[ ]`                                         |
| `requireArgs`        | Whether the command requires additional arguments                                   | `false`                                       |
| `confirm`            | Whether the command requires confirmation to proceed                                | `false`                                       |
| `raw`                | Whether you want the command to return raw shell output                             | `false`                                       |
| `aliases`            | Aliases for the command                                                             | `[ ]`                                         |
| `excludeShellChecks` | [shellcheck] rules to disable in the command                                        | `[ ]`                                         |

Here's an example:

```nix
{
  forrmat-rust = {
    command = "cargo fmt --all";
    packages = with pkgs; [
      cargo
      rustfmt
    ];
    description = "Format all Rust files in the repo";
    before = [ "build" ];
    after = [ "lint" ];
    aliases = [ "f" ];
  };
}
```

### Benchmark tasks

Up has a special function called `mkBenchmarkTask` that generates benchmarking tasks that use [hyperfine].
Here's an example task:

```nix
{
  run-benchmarks =
    pkgs.lib.mkBenchmarkTask {
      commands = [
        {
          name = "run";
          command = "./target/release/my-cli";
        }
      ];
      runs = 10;
    }
    // {
      description = "Benchmark the CLI";
    };
}
```

These attributes are available:

| Attribute        | Description                                                                         | Default          |
| :--------------- | :---------------------------------------------------------------------------------- | :--------------- |
| `commands`       | The commands to benchmark (a list of sets with the attributes `name` and `command`) |                  |
| `packages`       | A list of packages available to the `commands`                                      | `[]`             |
| `runs`           | The number of times to run the `commands`                                           |                  |
| `minRuns`        | The minimum number of times to run the `commands`                                   |                  |
| `maxRuns`        | The maximum number of times to run the `commands`                                   |                  |
| `setup`          | The command executed before all timing runs                                         |                  |
| `prepare`        | The command executed before each individual timing run                              |                  |
| `cleanup`        | The command executed once after all timing runs for a benchmark have completed      |                  |
| `exportJson`     | The path to which to export results as JSON                                         |                  |
| `exportMarkdown` | The path to which to export results as Markdown                                     |                  |
| `exportCsv`      | The path to which to export results as CSV                                          |                  |
| `parameterScan`  | [Parameter scan][params] parameters of the form `{ var, min, max, step? }`          |                  |
| `package`        | The Hyperfine package to use                                                        | `pkgs.hyperfine` |

### Watch tasks

Up has a special function called `mkWatch` that generates tasks monitored by [watchexec].
Here's an example task:

```nix
{
  rebuild-site =
    pkgs.lib.mkWatch {
      packages = [ pkgs.pnpm ];
      command = "pnpm run build";
      paths = [ "src/content" ];
    }
    // {
      description = "Rebuild site upon change";
    };
}
```

These attributes are available:

| Attribute            | Description                                                                 | Default          |
| :------------------- | :-------------------------------------------------------------------------- | :--------------- |
| `command`            | The command to re-run upon change                                           |                  |
| `packages`           | A list of packages available to the `command`                               | `[]`             |
| `paths`              | A list of paths to watch                                                    | `[ "." ]`        |
| `extensions`         | File extensions to watch                                                    | `[ ]`            |
| `ignore`             | A list of paths to ignore                                                   | `[ ]`            |
| `debounce`           | The number of milliseconds to debounce                                      |                  |
| `environment`        | Environment variables to pass to `command` (supports variables like `$PWD`) | `{ }`            |
| `package`            | The watchexec package to use                                                | `pkgs.watchexec` |
| `excludeShellChecks` | [shellcheck] rules to disable in the command                                | `[ ]`            |

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

## Tools

Up has a special function called `mkTool` that generates Bash scripts wrapping specific tools.
Here's an example:

```nix
let
  procs = pkgs.lib.mkTool {
    name = "procs";
    package = pkgs.bottom;
    args = [
      "--expanded"
      "--default_widget_type=proc"
    ];
  };
in
pkgs.mkShell {
  packages = [
    procs
  ];
}
```

It's essentially an intuitive convenience wrapper around [`writeShellApplication`][writeshellapplication].
These attributes are available:

| Attribute     | Description                                                                  | Default |
| :------------ | :--------------------------------------------------------------------------- | :------ |
| `name`        | The name of the runnable executable for the runner                           |         |
| `tool`        | The package available to the script                                          |         |
| `args`        | A list of arguments to pass to the package                                   | `[]`    |
| `environment` | Environment variables to pass to the script (supports variables like `$PWD`) | `{ }`   |

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
[depends-on]: https://f1bonacc1.github.io/process-compose/launcher#define-process-dependencies
[detsys]: https://determinate.systems
[flake-schemas]: https://github.com/DeterminateSystems/flake-schemas
[gum]: https://github.com/charmbracelet/gum
[hyperfine]: https://github.com/sharkdp/hyperfine
[liveness-probe]: https://f1bonacc1.github.io/process-compose/health/#liveness-probe
[params]: https://github.com/sharkdp/hyperfine?tab=readme-ov-file#parameterized-benchmarks
[process-compose]: https://f1bonacc1.github.io/process-compose
[readiness-probe]: https://f1bonacc1.github.io/process-compose/health/#readiness-probe
[shellcheck]: https://shellcheck.net
[shutdown]: https://f1bonacc1.github.io/process-compose/launcher/?h=shutdown#termination-parameters
[watchexec]: https://watchexec.github.io
[writeshellapplication]: https://ryantm.github.io/nixpkgs/builders/trivial-builders/#trivial-builder-writeShellApplication
