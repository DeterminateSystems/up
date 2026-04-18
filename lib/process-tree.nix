{
  lib,
  mkScript,
  pkgs,
  processModule,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

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
              watcherName = "${name}-watcher";
            in
            (lib.evalModules {
              modules = [
                processModule
                {
                  command = lib.concatStringsSep " " [
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
                  packages = [
                    pkgs.watchexec
                    config.package
                  ];
                  depends_on.${name}.condition = "process_started";
                }
              ];
              specialArgs = {
                name = watcherName;
              };
            }).config;

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
