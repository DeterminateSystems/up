{
  lib,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

  escapeSingleQuote = s: lib.replaceStrings [ "'" ] [ "'\"'\"'" ] s;

  runnerModule =
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = "act";
        };
        description = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        tasks = mkOption {
          type = types.attrsOf (types.submodule taskModule);
          default = { };
        };
        drv = mkOption {
          type = types.package;
          readOnly = true;
        };
      };

      config.drv =
        let
          listLines = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: task: ''
              printf '  %-20s %s\n' '${name}' '${
                lib.optionalString (task.description != null) escapeSingleQuote task.description
              }'
            '') config.tasks
          );

          caseArms = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: task: ''
              ${name})
                shift
                exec ${task.bin} "$@"
                ;;
            '') config.tasks
          );
        in
        pkgs.writeShellApplication {
          inherit (config) name;
          runtimeInputs = config.packages;
          text = ''
            if [[ $# -eq 0 || "$1" == "--list" || "$1" == "-l" ]]; then
              printf '%s - %s\n\n' '${config.name}' '${
                if config.description != null then
                  (escapeSingleQuote config.description)
                else
                  "Generated task runner"
              }'
              echo "Available tasks:"
              ${listLines}
              exit 0
            fi

            case "$1" in
              ${caseArms}
              *)
                echo "Unknown task: $1"
                echo "Run '${config.name} --list' to see available tasks"
                exit 1
                ;;
            esac
          '';
        }
        // lib.optionalAttrs (config.description != null) {
          inherit (config) description;
        };
    };
in
(lib.evalModules {
  modules = [
    runnerModule
    args
  ];
}).config.drv
