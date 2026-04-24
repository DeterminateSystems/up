{
  lib,
  pkgs,
}:

let
  mkWatchexecCmd =
    {
      command,
      paths ? [ "." ],
      extensions ? [ ],
      ignore ? [ ],
      debounce ? null,
      package ? pkgs.watchexec,
    }:
    assert lib.assertMsg (paths != [ ]) "mkWatchexecCmd: 'paths' must not be empty";
    let
      prefix = lib.escapeShellArgs (
        [ (lib.getExe package) ]
        ++ lib.concatMap (p: [
          "--watch"
          p
        ]) paths
        ++ lib.optionals (extensions != [ ]) [
          "--exts"
          (lib.concatStringsSep "," extensions)
        ]
        ++ lib.concatMap (p: [
          "--ignore"
          p
        ]) ignore
        ++ lib.optionals (debounce != null) [
          "--debounce"
          (toString debounce)
        ]
        ++ [ "--" ]
      );
    in
    "${prefix} ${command}";

  mkWatch =
    {
      command,
      paths ? [ "." ],
      extensions ? [ ],
      ignore ? [ ],
      debounce ? null,
      package ? pkgs.watchexec,
      packages ? [ ],
      ...
    }@args:
    let
      taskModuleArgs = builtins.removeAttrs args [
        "command"
        "paths"
        "extensions"
        "ignore"
        "debounce"
        "package"
        "packages"
      ];
      watchexecCmd = mkWatchexecCmd {
        inherit
          command
          paths
          extensions
          ignore
          debounce
          package
          ;
      };
    in
    taskModuleArgs
    // {
      raw = true;
      skip = true;
      packages = packages ++ [ package ];
      command = watchexecCmd;
    };

  mkWatchMany =
    {
      watchers,
      package ? pkgs.watchexec,
      packages ? [ ],
      exitMsg ? "Shutting down",
      ...
    }@args:
    assert lib.assertMsg (watchers != [ ]) "mkWatchMany: 'watchers' must not be empty";
    let
      taskModuleArgs = builtins.removeAttrs args [
        "watchers"
        "package"
        "packages"
        "exitMsg"
      ];

      # Resolve each watcher's package (explicit > shared default).
      watchexecPkg = map (w: w // { package = w.package or package; }) watchers;
      watcherCmds = map mkWatchexecCmd watchexecPkg;
      watcherPackages = map (w: w.package) watchexecPkg;

      command = ''
        pids=()

        shutdown() {
          trap - INT TERM
          echo "${exitMsg}" >&2
          kill "''${pids[@]}" 2>/dev/null
          wait "''${pids[@]}" 2>/dev/null
        }
        trap shutdown INT TERM

        ${lib.concatMapStringsSep "\n" (c: "${c} & pids+=($!)") watcherCmds}

        wait
      '';
    in
    taskModuleArgs
    // {
      raw = true;
      skip = true;
      packages = lib.unique (packages ++ watcherPackages);
      inherit command;
    };
in
{
  inherit mkWatch mkWatchMany;
}
