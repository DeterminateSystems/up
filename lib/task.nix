{ lib, pkgs }:

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
    command = mkOption {
      type = types.str;
    };
    requireArgs = mkOption {
      type = types.bool;
      default = false;
    };
    packages = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    description = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    excludeShellChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    confirm = mkOption {
      type = types.either types.bool types.str;
      default = false;
      description = "Prompt for confirmation before running. Can be a bool or a custom message.";
    };
    environment = mkOption {
      type = types.either (types.attrsOf types.str) (types.listOf types.str);
      default = { };
    };
    before = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Tasks that this task must run before.";
    };
    after = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Tasks that must complete before this task runs.";
    };
    status = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command to check if the task needs to run. Exit 0 means skip.";
    };

    # colors
    errorColor = mkOption {
      type = types.str;
      default = "1";
    };
    mutedColor = mkOption {
      type = types.str;
      default = "240";
    };

    # generated
    bin = mkOption {
      type = types.str;
      readOnly = true;
    };
    drv = mkOption {
      type = types.package;
      readOnly = true;
    };
  };

  config =
    let
      taskName = if config.name != null then config.name else name;
      isStatic = v: !(lib.hasInfix "$" v);
      envAttrs =
        if builtins.isAttrs config.environment then
          config.environment
        else
          builtins.listToAttrs (
            map (
              s:
              let
                parts = lib.splitString "=" s;
              in
              {
                name = builtins.head parts;
                value = lib.concatStringsSep "=" (builtins.tail parts);
              }
            ) config.environment
          );
      staticEnv = lib.filterAttrs (_: isStatic) envAttrs;
      dynamicEnv = lib.filterAttrs (_: v: !isStatic v) envAttrs;
      escapeForDoubleQuotes = v: lib.replaceStrings [ "\\" "\"" "`" "!" ] [ "\\\\" "\\\"" "\\`" "\\!" ] v;
    in
    {
      drv =
        let
          baseDrv = pkgs.writeShellApplication {
            name = taskName;
            runtimeInputs = lib.unique (config.packages ++ [ pkgs.gum ]);
            runtimeEnv = staticEnv;
            inherit (config) excludeShellChecks;
            text = lib.concatStringsSep "\n" (
              lib.filter (s: s != "") [
                (lib.optionalString (config.confirm != false) ''
                  if ! gum confirm ${
                    if builtins.isString config.confirm then ''"${config.confirm}"'' else ''"Run ${taskName}?"''
                  }; then
                    gum style --foreground ${config.mutedColor} "⊘ ${taskName} cancelled"
                    exit 2
                  fi
                '')
                (lib.optionalString config.requireArgs ''
                  if [[ $# -eq 0 ]]; then
                    gum style --foreground ${config.errorColor} "✗ ${taskName}: arguments required"
                    exit 1
                  fi
                '')
                (lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (k: v: ''export ${k}="${escapeForDoubleQuotes v}"'') dynamicEnv
                ))
                (if config.requireArgs then "${config.command} \"$@\"" else config.command)
              ]
            );
            meta = lib.optionalAttrs (config.description != null) {
              inherit (config) description;
            };
          };
        in
        baseDrv
        // lib.optionalAttrs (config.description != null) {
          inherit (config) description;
        };

      bin = lib.getExe config.drv;
    };
}
