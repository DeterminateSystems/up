{
  lib,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

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
              printf '  %-20s %s\n' '${name}' '${lib.optionalString (task.description != null) task.description}'
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

          dispatcher = pkgs.writeShellApplication {
            inherit (config) name;
            text = ''
              if [[ $# -eq 0 || "$1" == "--list" || "$1" == "-l" ]]; then
                printf '%s - %s\n\n' '${config.name}' '${
                  if config.description != null then config.description else "Generated task runner"
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
          };

          zshCompletions = pkgs.writeTextFile {
            name = "${config.name}-completions-zsh";
            destination = "/share/zsh/site-functions/_${config.name}";
            text = ''
              #compdef ${config.name}
              _${config.name}() {
                local -a tasks
                tasks=(${
                  lib.concatMapStringsSep "" (entry: "\n      ${entry}") (
                    lib.mapAttrsToList (
                      name: task: if task.description != null then "\"${name}:${task.description}\"" else "\"${name}\""
                    ) config.tasks
                  )
                }
                )
                _describe 'task' tasks
              }
              _${config.name}
            '';
          };

          bashCompletions = pkgs.writeTextFile {
            name = "${config.name}-completions-bash";
            destination = "/share/bash-completion/completions/${config.name}";
            text = ''
              _${config.name}() {
                local cur=''${COMP_WORDS[COMP_CWORD]}
                COMPREPLY=($(compgen -W '${lib.concatStringsSep " " (builtins.attrNames config.tasks)}' -- "$cur"))
              }
              complete -F _${config.name} ${config.name}
            '';
          };

          fishCompletions = pkgs.writeTextFile {
            name = "${config.name}-completions-fish";
            destination = "/share/fish/vendor_completions.d/${config.name}.fish";
            text = ''
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: task:
                  if task.description != null then
                    "complete -c ${config.name} -f -a '${name}' -d '${task.description}'"
                  else
                    "complete -c ${config.name} -f -a '${name}'"
                ) config.tasks
              )}
            '';
          };
        in
        pkgs.symlinkJoin {
          name = config.name;
          paths = [
            dispatcher
            zshCompletions
            bashCompletions
            fishCompletions
          ];
          passthru.shellHook = ''
            case "$(basename "$SHELL")" in
              zsh)
                fpath=(${zshCompletions}/share/zsh/site-functions $fpath)
                autoload -Uz compinit && compinit
                ;;
              bash)
                source ${bashCompletions}/share/bash-completion/completions/${config.name}
                ;;
              fish)
                source ${fishCompletions}/share/fish/vendor_completions.d/${config.name}.fish
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
