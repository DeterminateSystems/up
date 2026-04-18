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
    environment = mkOption {
      type = types.either (types.attrsOf types.str) (types.listOf types.str);
      default = { };
    };
    requireArgs = mkOption {
      type = types.bool;
      default = false;
    };
    packages = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    raw = mkOption {
      type = types.bool;
      default = false;
      description = "Stream output directly without capturing (preserves colors and formatting).";
    };
    aliases = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    excludeShellChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    confirm = mkOption {
      type = types.bool;
      default = false;
    };
    before = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    after = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    # colors
    errorColor = lib.mkOption {
      type = lib.types.str;
      default = "1";
    };
    mutedColor = lib.mkOption {
      type = lib.types.str;
      default = "248";
    };

    # generated
    bin = mkOption {
      type = types.str;
      readOnly = true;
    };
    script = mkOption {
      type = types.package;
      readOnly = true;
    };
  };

  config =
    let
      script =
        let
          taskName = if config.name != null then config.name else name;
          resolvedCommand =
            if builtins.isString config.command then config.command else lib.getExe config.command;
        in
        mkScript {
          name = "__up_task_${taskName}";
          packages = config.packages ++ lib.optional (config.confirm || config.requireArgs) pkgs.gum;
          inherit (config) environment excludeShellChecks;
          command = lib.concatStringsSep "\n" (
            lib.optionals config.requireArgs [
              ''
                if [[ $# -eq 0 ]]; then
                  gum style --foreground ${config.errorColor} "✗ ${taskName}: arguments required"
                  exit 1
                fi
              ''
            ]
            ++ [ (if config.requireArgs then ''${resolvedCommand} "$@"'' else resolvedCommand) ]
          );
        };
    in
    {
      inherit script;

      bin = lib.getExe config.script;
    };
}
