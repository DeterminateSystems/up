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
    command = mkOption {
      type = types.either types.str types.package;
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
    description = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    excludeShellChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    confirm = mkOption {
      type = types.bool;
      default = false;
    };
    environment = mkOption {
      type = types.either (types.attrsOf types.str) (types.listOf types.str);
      default = { };
    };
    before = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    after = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    status = mkOption {
      type = types.nullOr types.str;
      default = null;
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

  config = {
    script =
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

        resolvedCommand =
          if builtins.isString config.command then config.command else lib.getExe config.command;
      in
      mkScript {
        name = "__up_task_${taskName}";
        packages = config.packages ++ lib.optional (config.confirm || config.requireArgs) pkgs.gum;
        environment = staticEnv;
        inherit (config) excludeShellChecks;
        command = lib.concatStringsSep "\n" (
          lib.filter (s: s != "") [
            (lib.optionalString config.requireArgs ''
              if [[ $# -eq 0 ]]; then
                gum style --foreground ${config.errorColor} "✗ ${taskName}: arguments required"
                exit 1
              fi
            '')
            (lib.concatStringsSep "\n" (
              lib.mapAttrsToList (k: v: ''export ${k}="${escapeForDoubleQuotes v}"'') dynamicEnv
            ))
            (lib.optionalString (config.status != null) ''
              _status_exit=0
              (${lib.trim config.status}) || _status_exit=$?
              if [[ $_status_exit -ne 0 ]]; then
                gum style --foreground ${config.mutedColor} "⊘ ${taskName} skipped (status check failed)"
                exit 0
              fi
            '')
            (if config.requireArgs then "${resolvedCommand} \"$@\"" else resolvedCommand)
          ]
        );
      };

    bin = lib.getExe config.script;
  };
}
