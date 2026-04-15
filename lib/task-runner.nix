{
  lib,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

  escapeSingleQuote = s: lib.replaceStrings [ "'" ] [ "'\"'\"'" ] s;

  isTask = v: builtins.isAttrs v && v ? __isTask && v.__isTask;

  resolveTask =
    name: v:
    if isTask v then
      v
    else
      (lib.evalModules {
        modules = [
          taskModule
          { config._module.args.name = name; }
          v
        ];
      }).config;

  # Topological sort to return an ordered list of task names
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
          rest = builtins.filter hasUnresolvedDep remaining;
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
          default = "tasks";
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
          type = types.attrsOf types.anything;
          default = { };
        };
        drv = mkOption {
          type = types.package;
          readOnly = true;
        };
      };

      config.drv =
        let
          inherit (pkgs) gum;

          resolvedTasks =
            assert lib.assertMsg (
              !builtins.hasAttr "all" config.tasks
            ) "mkTaskRunner: '${config.name}' has a task named 'all', which is reserved";
            lib.mapAttrs resolveTask config.tasks;

          inherit (topo) edges;
          topo = topoSort resolvedTasks;
          orderedNames = topo.ordered;
          orderedTasks = map (n: {
            name = n;
            task = resolvedTasks.${n};
          }) orderedNames;

          header =
            if config.description != null then
              ''gum style --border rounded --padding "0 1" --bold "${config.name} — ${escapeSingleQuote config.description}"''
            else
              ''gum style --border rounded --padding "0 1" --bold "${config.name}"'';

          listLines = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              let
                desc = if task.description != null then escapeSingleQuote task.description else "";
              in
              ''
                printf '  %s  %s\n' \
                  "$(gum style --foreground 212 '${name}')" \
                  "$(gum style --foreground 240 '${desc}')"
              ''
            ) orderedTasks
          );

          runStep = name: bin: ''
            if gum spin --spinner dot --show-output --title "$(gum style --foreground 212 '[${name}]') running..." -- ${bin}; then
              gum style --foreground 2 "✓ ${name}"
            else
              gum style --foreground 1 "✗ ${name} failed"
              exit 1
            fi
          '';

          caseArms = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              let
                deps = builtins.filter (
                  depName: builtins.any (e: e.from == depName && e.to == name) edges
                ) orderedNames;
                depSteps = lib.concatStringsSep "\n" (map (dep: runStep dep resolvedTasks.${dep}.bin) deps);
              in
              ''
                ${name})
                  shift
                  ${depSteps}
                  ${runStep name task.bin}
                  ;;
              ''
            ) orderedTasks
          );

          runAllSteps = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              if task.status or null != null then
                ''
                  if ${task.status}; then
                    gum style --foreground 240 "⊘ ${name} skipped"
                  else
                    ${runStep name task.bin}
                  fi
                ''
              else
                runStep name task.bin
            ) orderedTasks
          );

          commandText = ''
            if [[ $# -eq 0 || "$1" == "--list" || "$1" == "-l" ]]; then
              ${header}
              echo ""
              gum style --bold "Available tasks:"
              echo ""
              ${listLines}
              echo ""
              printf '  %s  %s\n' \
                "$(gum style --foreground 212 'all')" \
                "$(gum style --foreground 240 'Run all tasks in dependency order')"
              echo ""
              exit 0
            fi

            case "$1" in
              all)
                ${runAllSteps}
                ;;
              ${caseArms}
              *)
                gum style --foreground 1 "Unknown task: $1"
                echo "Run '${config.name} --list' to see available tasks"
                exit 1
                ;;
            esac
          '';
        in
        pkgs.writeShellApplication {
          inherit (config) name;
          runtimeInputs = lib.unique (config.packages ++ [ gum ]);
          text = commandText;
        }
        // {
          command = commandText;
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
