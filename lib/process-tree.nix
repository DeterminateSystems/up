{
  lib,
  mkScript,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

  dependencyModule = {
    options.condition = mkOption {
      type = types.enum [
        "process_completed"
        "process_completed_successfully"
        "process_healthy"
        "process_started"
        "process_log"
      ];
      default = "process_started";
    };
  };

  execModule = {
    options = {
      command = mkOption {
        type = types.str;
      };
      working_dir = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  probeModule = {
    options = {
      exec = mkOption {
        type = types.nullOr (types.submodule execModule);
        default = null;
      };
      initial_delay_seconds = mkOption {
        type = types.int;
        default = 0;
      };
      period_seconds = mkOption {
        type = types.ints.positive;
        default = 10;
      };
      timeout_seconds = mkOption {
        type = types.ints.positive;
        default = 1;
      };
      failure_threshold = mkOption {
        type = types.ints.positive;
        default = 3;
      };
    };
  };

  shutdownModule = {
    options = {
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      signal = mkOption {
        type = types.int;
        default = 15; # SIGTERM
      };
      timeout_seconds = mkOption {
        type = types.ints.positive;
        default = 10;
      };
      parent_only = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  processModule =
    { name, ... }:
    {
      options = {
        command = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        working_dir = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        watch = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                paths = lib.mkOption {
                  type = types.nonEmptyListOf lib.types.str;
                };
                debounce = lib.mkOption {
                  type = lib.types.int;
                  default = 500;
                };
                ignore = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                action = lib.mkOption {
                  type = lib.types.enum [
                    "restart"
                    "stop"
                    "start"
                  ];
                  default = "restart";
                };
              };
            }
          );
          default = null;
        };
        environment = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        depends_on = mkOption {
          type = types.attrsOf (types.submodule dependencyModule);
          default = { };
        };
        readiness_probe = mkOption {
          type = types.nullOr (types.submodule probeModule);
          default = null;
        };
        liveness_probe = mkOption {
          type = types.nullOr (types.submodule probeModule);
          default = null;
        };
        shutdown = mkOption {
          type = types.nullOr (types.submodule shutdownModule);
          default = null;
        };
        excludeShellChecks = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
    };

  processTreeModule =
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = "run-process-tree";
        };
        package = mkOption {
          type = types.package;
          default = pkgs.process-compose;
        };
        environment = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        log_level = mkOption {
          type = types.enum [
            "info"
            "trace"
            "debug"
            "warn"
            "error"
            "fatal"
            "panic"
          ];
          default = "info";
        };
        configFileName = mkOption {
          type = types.str;
          default = "process-compose.yaml";
        };
        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        excludeShellChecks = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        processes = mkOption {
          type = types.attrsOf (types.submodule processModule);
          default = { };
          apply = v: if v == { } then throw "mkProcessTree: '${config.name}' has no processes" else v;
        };

        # generated
        script = mkOption {
          type = types.package;
          readOnly = true;
        };
      };

      config.script =
        let
          stripNulls = lib.filterAttrs (_: v: v != null);

          serializeProcess =
            name: proc:
            stripNulls {
              inherit (proc) working_dir;

              command =
                let
                  script = mkScript {
                    name = "run-${name}";
                    inherit (proc) command environment packages;
                    excludeShellChecks = lib.unique (config.excludeShellChecks ++ proc.excludeShellChecks);
                  };
                in
                "${script}/bin/run-${name}";

              depends_on = if proc.depends_on == { } then null else proc.depends_on;
              environment = null;
              liveness_probe =
                if proc.liveness_probe == null then
                  null
                else
                  stripNulls {
                    exec =
                      if proc.liveness_probe.exec == null then null else { inherit (proc.liveness_probe.exec) command; };
                    inherit (proc.liveness_probe)
                      initial_delay_seconds
                      period_seconds
                      timeout_seconds
                      failure_threshold
                      ;
                  };

              readiness_probe =
                if proc.readiness_probe == null then
                  null
                else
                  stripNulls {
                    exec =
                      if proc.readiness_probe.exec == null then
                        null
                      else
                        { inherit (proc.readiness_probe.exec) command; };
                    inherit (proc.readiness_probe)
                      initial_delay_seconds
                      period_seconds
                      timeout_seconds
                      failure_threshold
                      ;
                  };

              shutdown =
                if proc.shutdown == null then
                  null
                else
                  stripNulls {
                    inherit (proc.shutdown)
                      command
                      parent_only
                      signal
                      timeout_seconds
                      ;
                  };
            };

          mkWatcher =
            name: proc:
            let
              w = proc.watch;
            in
            {
              packages = [
                pkgs.watchexec
                config.package
              ];

              command = lib.concatStringsSep " " [
                "exec"
                "watchexec"
                (lib.concatMapStringsSep " " (p: "--watch '${toString p}'") w.paths)
                (lib.concatMapStringsSep " " (i: "--ignore '${i}'") w.ignore)
                "--debounce"
                "${toString w.debounce}ms"
                "--postpone"
                "--on-busy-update"
                "queue"
                "--"
                "process-compose"
                "process"
                w.action
                name
              ];

              depends_on.${name}.condition = "process_started";

              # defaults the processModule would provide — watchers bypass it
              environment = { };
              excludeShellChecks = [ ];
              working_dir = null;
              readiness_probe = null;
              liveness_probe = null;
              shutdown = null;
              watch = null;
              description = null;
            };

          watcherProcesses = lib.mapAttrs' (
            name: proc: lib.nameValuePair "${name}-watcher" (mkWatcher name proc)
          ) (lib.filterAttrs (_: p: p.watch != null) config.processes);

          allProcesses = config.processes // watcherProcesses;

          configFile =
            pkgs.runCommand config.configFileName
              {
                json = builtins.toJSON (stripNulls {
                  inherit (config) log_level;
                  log_location = "/tmp/pc-debug.log";
                  processes = lib.mapAttrs serializeProcess allProcesses;
                });
                passAsFile = [ "json" ];
                nativeBuildInputs = [ pkgs.yq-go ];
              }
              ''
                yq -P '.' "$jsonPath" > $out
              '';

          allPackages = lib.unique ([ config.package ] ++ config.packages);

          commandText = lib.concatStringsSep " " [
            "process-compose"
            "up"
            "--config"
            configFile
          ];

          script = mkScript {
            inherit (config) name excludeShellChecks environment;
            packages = allPackages;
            command = commandText;
          };
        in
        script
        // {
          script = builtins.readFile "${script}/bin/${config.name}";
          config = builtins.readFile configFile;
          processes = lib.mapAttrs (
            name: proc:
            proc
            // {
              inherit name;
              resolved =
                let
                  val = serializeProcess name proc;
                in
                val // { command = builtins.readFile val.command; };
            }
          ) config.processes;
        };
    };
in
(lib.evalModules {
  modules = [
    processTreeModule
    args
  ];
}).config.script
