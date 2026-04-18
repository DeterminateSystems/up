{
  lib,
  mkScript,
  pkgs,
}:

{
  config,
  name,
  ...
}:

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
      command = mkOption { type = types.str; };
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

  watchModule = {
    options = {
      paths = mkOption {
        type = types.nonEmptyListOf types.str;
      };
      debounce = mkOption {
        type = types.int;
        default = 500;
      };
      ignore = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      action = mkOption {
        type = types.enum [
          "restart"
          "stop"
          "start"
        ];
        default = "restart";
      };
    };
  };
in
{
  options = {
    name = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    description = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    command = mkOption {
      type = types.either types.str types.package;
    };
    working_dir = mkOption {
      type = types.nullOr types.str;
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
    excludeShellChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
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
    watch = mkOption {
      type = types.nullOr (types.submodule watchModule);
      default = null;
    };

    # generated
    script = mkOption {
      type = types.package;
      readOnly = true;
    };
    bin = mkOption {
      type = types.str;
      readOnly = true;
    };
  };

  config =
    let
      procName = if config.name != null then config.name else name;
      resolvedCommand =
        if builtins.isString config.command then config.command else lib.getExe config.command;
    in
    {
      script = mkScript {
        name = "run-${procName}";
        inherit (config) environment packages excludeShellChecks;
        command = resolvedCommand;
      };
      bin = lib.getExe config.script;
    };
}
