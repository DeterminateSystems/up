{
  lib,
  mkScript,
  pkgs,
  taskModule,
}:

args:

let
  inherit (lib) mkOption types;

  escapeSingleQuote = s: lib.replaceStrings [ "'" ] [ "'\"'\"'" ] s;

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
        aliases = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        environment = mkOption {
          type = types.either (types.attrsOf types.str) (types.listOf types.str);
          default = { };
        };
        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        tasks = mkOption {
          type = types.attrsOf types.anything;
          default = { };
        };

        # colors
        accentColor = mkOption {
          type = types.str;
          default = "212";
        };
        successColor = mkOption {
          type = types.str;
          default = "2";
        };
        errorColor = lib.mkOption {
          type = lib.types.str;
          default = "1";
        };
        mutedColor = lib.mkOption {
          type = lib.types.str;
          default = "248";
        };

        # generated
        script = mkOption {
          type = types.package;
          readOnly = true;
        };
      };

      config.script =
        let
          inherit (pkgs) gum;

          resolvedTasks =
            let
              resolveTask =
                name: v:
                (lib.evalModules {
                  modules = [
                    taskModule
                    { config._module.args.name = name; }
                    { inherit (config) errorColor mutedColor; }
                  ]
                  ++ (if builtins.isList v then v else [ v ]);
                }).config;
            in
            assert lib.assertMsg (config.tasks != { }) "mkTaskRunner: '${config.name}' has no tasks";
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

          inherit (config)
            accentColor
            errorColor
            mutedColor
            successColor
            ;

          header =
            if config.description != null then
              ''gum style --border rounded --padding "0 1" --bold "${config.name} — ${escapeSingleQuote config.description}"''
            else
              ''gum style --border rounded --padding "0 1" --bold "${config.name}"'';

          listLines =
            let
              allNames = map ({ name, ... }: name) orderedTasks ++ [ "all" ];
              maxLen = lib.foldl (
                acc: n: if lib.stringLength n > acc then lib.stringLength n else acc
              ) 0 allNames;
              accent = "\\e[38;5;${accentColor}m";
              muted = "\\e[38;5;${mutedColor}m";
              reset = "\\e[0m";
              mkRow =
                name: desc: aliases:
                let
                  spaces = lib.concatStringsSep "" (lib.genList (_: " ") (maxLen - lib.stringLength name + 2));
                  aliasStr = lib.optionalString (aliases != [ ]) " [${lib.concatStringsSep ", " aliases}]";
                in
                "  ${accent}${name}${reset}${spaces}  ${muted}${escapeSingleQuote desc}${aliasStr}${reset}";
              rows =
                map (
                  { name, task }:
                  mkRow name (
                    if task.description != null then escapeSingleQuote task.description else ""
                  ) task.aliases
                ) orderedTasks
                ++ [ (mkRow "all" "Run all tasks in dependency order" [ ]) ];
            in
            ''echo -e "${lib.concatStringsSep "\\n" rows}"'';

          runStep = name: bin: args: raw: ''
            gum style --foreground ${accentColor} '▶ ${name}'
            echo ""
            set +e
            ${
              if raw then
                ''
                  ${bin} ${args}
                  _exit=$?
                ''
              else
                ''
                  _output=$(${bin} ${args} 2>&1)
                  _exit=$?
                ''
            }
            set -e
            ${lib.optionalString (!raw) ''
              if [[ -n "$_output" ]]; then
                echo "$_output" | awk '/^[[:space:]]*$/{blank++; next} {for(i=0;i<blank;i++) print ""; blank=0; print}' | gum style --margin "0 0 0 2"
              fi
            ''}
            echo ""
            if [[ "''${_exit}" -ne 0 ]]; then
              gum style --foreground ${errorColor} "✗ ${name} failed (exit code ''${_exit})"
              exit "''${_exit}"
            else
              gum style --foreground ${successColor} "✓ ${name}"
            fi
          '';

          caseArms = lib.concatStringsSep "\n" (
            map (
              { name, task }:
              let
                deps = builtins.filter (
                  depName: builtins.any (e: e.from == depName && e.to == name) edges
                ) orderedNames;
                depSteps = lib.concatStringsSep "\n" (
                  map (dep: runStep dep resolvedTasks.${dep}.bin "" resolvedTasks.${dep}.raw) deps
                );
                mainArm = ''
                  ${name})
                    shift
                    ${depSteps}
                    ${lib.optionalString task.confirm ''
                      if ! gum confirm "Run ${name}?"; then
                        gum style --foreground ${mutedColor} "⊘ ${name} cancelled"
                        exit 0
                      fi
                    ''}
                    ${runStep name task.bin (if task.requireArgs then ''"$@"'' else "") task.raw}
                    ;;
                '';
                aliasArms = lib.concatStringsSep "\n" (
                  map (alias: ''
                    ${alias})
                      shift
                      exec "$0" ${name} "$@"
                      ;;
                  '') task.aliases
                );
              in
              mainArm + aliasArms
            ) orderedTasks
          );

          runAllSteps =
            let
              tasks = lib.partition ({ task, ... }: !task.raw && !task.skip && !task.requireArgs) orderedTasks;
              skipped = tasks.wrong;
              runnable = tasks.right;

              steps = lib.concatStringsSep "\n" (
                map (
                  { name, task }:
                  if task.requireArgs then
                    ''gum style --foreground ${mutedColor} "⊘ ${name} skipped (requires arguments)"''
                  else if task.confirm then
                    ''
                      if gum confirm "Run ${name}?"; then
                        ${runStep name task.bin "" task.raw}
                      else
                        gum style --foreground ${mutedColor} "⊘ ${name} cancelled"
                      fi
                    ''
                  else
                    runStep name task.bin "" task.raw
                ) runnable
              );
            in
            lib.concatStringsSep "\n" (
              lib.filter (s: s != "") [
                steps
                (lib.optionalString (skipped != [ ]) ''
                  echo ""
                  gum style --foreground ${mutedColor} "These tasks were skipped:"
                  gum style --foreground ${accentColor} "  ${
                    lib.concatStringsSep " " (map ({ name, ... }: name) skipped)
                  }"
                '')

              ]
            );

          commandText = ''
            if [[ $# -eq 0 ]]; then
              ${header}
              echo ""
              gum style --bold "Available tasks:"
              echo ""
              ${listLines}
              echo ""
              exit 0
            fi

            case "$1" in
              all)
                ${runAllSteps}
                ;;
              ${caseArms}
              *)
                gum style --foreground ${errorColor} "Unknown task: $1"
                echo "Run '${config.name}' with no arguments to see available tasks"
                exit 1
                ;;
            esac
          '';

          baseScript = mkScript {
            inherit (config) name environment;
            packages = lib.unique (config.packages ++ [ gum ]);
            command = commandText;
          };

          script =
            if config.aliases == [ ] then
              baseScript
            else
              pkgs.symlinkJoin {
                inherit (config) name;
                paths = [ baseScript ];
                postBuild = lib.concatMapStringsSep "\n" (
                  alias: "ln -s ${config.name} $out/bin/${alias}"
                ) config.aliases;
              };
        in
        script
        // {
          command = commandText;
          tasks = lib.mapAttrs (_: task: {
            inherit (task) description;
            command = lib.getExe task.script;
            before = task.before or [ ];
            after = task.after or [ ];
          }) resolvedTasks;
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
}).config.script
