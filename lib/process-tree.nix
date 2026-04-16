{
  lib,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

  toEnvList = env: if builtins.isList env then env else lib.mapAttrsToList (k: v: "${k}=${v}") env;
  toExport =
    e:
    let
      key = builtins.head (builtins.split "=" e);
      val = lib.removePrefix "${key}=" e;
    in
    if lib.hasInfix "$(" val then
      ''${key}="${val}"'' + "\n" + "export ${key}"
    else
      ''export ${key}="${val}"'';

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
        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        staticEnvVars = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        runtimeEnvVars = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
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

  processesModule =
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = "run-process-tree";
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.process-compose;
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
        staticEnvVars = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        runtimeEnvVars = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        excludeShellChecks = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        processes = mkOption {
          type = types.attrsOf (types.submodule processModule);
          default = { };
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
          toEnvList = env: if builtins.isList env then env else lib.mapAttrsToList (k: v: "${k}=${v}") env;
          serializeProcess =
            name: proc:
            let
              environment = toEnvList proc.staticEnvVars;
            in
            stripNulls {
              inherit (proc) working_dir;

              command =
                let
                  envList = toEnvList proc.runtimeEnvVars;
                  exports = lib.concatStringsSep "\n" (map toExport envList);
                  script = pkgs.writeShellApplication {
                    name = "run-${name}";
                    excludeShellChecks = lib.unique (config.excludeShellChecks ++ proc.excludeShellChecks);
                    text = lib.concatStringsSep "\n\n" (
                      lib.filter (s: s != "") [
                        (lib.optionalString (envList != [ ]) exports)
                        proc.command
                      ]
                    );
                  };
                in
                "${script}/bin/run-${name}";

              depends_on = if proc.depends_on == { } then null else proc.depends_on;
              environment = if environment == [ ] then null else environment;
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

          runtimeExports = lib.concatStringsSep "\n" (map toExport (toEnvList config.runtimeEnvVars));

          configFile =
            pkgs.runCommand config.configFileName
              {
                json = builtins.toJSON (stripNulls {
                  inherit (config) log_level;
                  log_location = "/tmp/pc-debug.log";
                  environment =
                    let
                      envList = toEnvList config.staticEnvVars;
                    in
                    if envList == [ ] then null else envList;
                  processes = lib.mapAttrs serializeProcess config.processes;
                });
                passAsFile = [ "json" ];
                nativeBuildInputs = [ pkgs.yq-go ];
              }
              ''
                yq -P '.' "$jsonPath" > $out
              '';

          allPackages = lib.unique (
            [ config.package ]
            ++ config.packages
            ++ lib.flatten (lib.mapAttrsToList (_: proc: proc.packages) config.processes)
          );

          commandText =
            let
              processComposeCommand = lib.concatStringsSep " " [
                "process-compose"
                "up"
                "--config"
                configFile
              ];

              parts = lib.filter (s: s != "") [
                (lib.optionalString (toEnvList config.runtimeEnvVars != [ ]) (lib.removeSuffix "\n" runtimeExports))
                processComposeCommand
              ];
            in
            lib.concatStringsSep "\n\n" parts;

          script = pkgs.writeShellApplication {
            inherit (config) name excludeShellChecks;
            runtimeInputs = allPackages;
            text = commandText;
          };
        in
        script
        // lib.optionalAttrs (config.description != null) {
          inherit (config) description;
        }
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
    processesModule
    args
  ];
}).config.script
