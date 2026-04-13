{
  lib,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

  escapeSingleQuote = s: lib.replaceStrings [ "'" ] [ "'\"'\"'" ] s;

  # Topological sort - returns ordered list of task names
  topoSort =
    tasks:
    let
      taskNames = builtins.attrNames tasks;

      edges = lib.flatten (
        lib.mapAttrsToList (
          taskName: task:
          map (dep: {
            from = dep;
            to = taskName;
          }) task.after
          ++ map (dep: {
            from = taskName;
            to = dep;
          }) task.before
        ) tasks
      );

      sort =
        remaining: resolvedEdges:
        let
          hasUnresolvedDep =
            name: builtins.any (e: e.to == name && builtins.elem e.from remaining) resolvedEdges;
          ready = builtins.filter (n: !hasUnresolvedDep n) remaining;
          rest = builtins.filter (n: hasUnresolvedDep n) remaining;
        in
        if remaining == [ ] then
          [ ]
        else if ready == [ ] then
          throw "mkTaskRunner: cycle detected among: ${lib.concatStringsSep ", " remaining}"
        else
          ready ++ sort rest (builtins.filter (e: !builtins.elem e.from ready) resolvedEdges);
    in
    {
      ordered = sort taskNames edges;
      inherit edges;
    };

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
          topo = topoSort config.tasks;
          orderedNames = topo.ordered;
          edges = topo.edges;
          orderedTasks = map (n: {
            name = n;
            task = config.tasks.${n};
          }) orderedNames;

          listLines = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              ''
                printf '  %-20s %s\n' '${name}' '${
                  lib.optionalString (task.description != null) (escapeSingleQuote task.description)
                }'
              ''
            ) orderedTasks
          );

          caseArms = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              let
                deps = builtins.filter (
                  depName: builtins.any (e: e.from == depName && e.to == name) edges
                ) orderedNames;
                depSteps = lib.concatStringsSep "\n" (
                  map (depName: ''
                    echo "[${depName}] running..."
                    ${config.tasks.${depName}.bin}
                  '') deps
                );
              in
              ''
                ${name})
                  shift
                  ${depSteps}
                  exec ${task.bin} "$@"
                  ;;
              ''
            ) orderedTasks
          );

          runAllSteps = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              ''
                echo "[${name}] running..."
                ${task.bin}
              ''
              + lib.optionalString (task.status or null != null) ''
                if ${task.status}; then
                  echo "[${name}] skipped (already done)"
                else
                  echo "[${name}] running..."
                  ${task.bin}
                fi
              ''
            ) orderedTasks
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
              echo ""
              printf '  %-20s %s\n' 'all' 'Run all tasks in dependency order'
              exit 0
            fi

            case "$1" in
              all)
                ${runAllSteps}
                ;;
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
