{
  lib,
  pkgs,
  taskModule,
}:

module:

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
        type = types.str;
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

  processModule =
    { name, ... }:
    {
      options = {
        command = mkOption {
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
        environment = mkOption {
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
        environment = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        processes = mkOption {
          type = types.attrsOf (types.submodule processModule);
          default = { };
        };
        drv = mkOption {
          type = types.package;
          readOnly = true;
        };
      };

      config.drv =
        let
          stripNulls = lib.filterAttrs (_: v: v != null);
          toEnvList = env: if builtins.isList env then env else lib.mapAttrsToList (k: v: "${k}=${v}") env;
          serializeProcess =
            proc:
            let
              allPackages = lib.unique (config.packages ++ proc.packages);
              binPaths = map (p: "${p}/bin") allPackages;
              environment = toEnvList proc.environment;
            in
            stripNulls {
              inherit (proc) command;
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
            };

          configFile =
            pkgs.runCommand config.configFileName
              {
                json = builtins.toJSON {
                  inherit (config) log_level;
                  log_location = "/tmp/pc-debug.log";
                  environment = toEnvList config.environment;
                  processes = lib.mapAttrs (_: serializeProcess) config.processes;
                };
                passAsFile = [ "json" ];
                nativeBuildInputs = [ pkgs.yq-go ];
              }
              ''
                yq -P '.' "$jsonPath" > $out
              '';
        in
        pkgs.writeShellApplication {
          inherit (config) name;
          runtimeInputs = [ config.package ];
          text = ''
            export PATH="${lib.concatStringsSep ":" (map (p: "${p}/bin") config.packages)}:$PATH"

            process-compose up \
              --config ${configFile}
          '';
        }
        // lib.optionalAttrs (config.description != null) {
          inherit (config) description;
        }
        // {
          config = configFile;
        };
    };
in
(lib.evalModules {
  modules = [
    processesModule
    module
  ];
}).config.drv
