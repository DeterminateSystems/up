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
    excludeShellChecks = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    environment = mkOption {
      type = types.either (types.attrsOf types.str) (types.listOf types.str);
      default = { };
    };
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
        if config.command == null then
          assert lib.assertMsg (
            config.packages != [ ]
          ) "taskModule: '${taskName}' must have either a command or at least one package";
          builtins.head config.packages
        else
          pkgs.writeShellApplication {
            name = taskName;
            runtimeInputs = config.packages;
            runtimeEnv = staticEnv;
            inherit (config) excludeShellChecks;
            text = ''
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (k: v: ''export ${k}="${escapeForDoubleQuotes v}"'') dynamicEnv
              )}
              ${config.command}
            '';
            meta = lib.optionalAttrs (config.description != null) {
              inherit (config) description;
            };
          };

      bin =
        if config.command == null then
          lib.getExe' (builtins.head config.packages) (
            (builtins.head config.packages).meta.mainProgram or (lib.getName (builtins.head config.packages))
          )
        else
          lib.getExe config.drv;
    };
}
