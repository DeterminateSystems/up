{
  lib,
  mkProcessTree,
  pkgs,
}:

let
  mkWatchexecCmd =
    {
      name ? "watch",
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
      name ? "watch-all",
      watchers,
      package ? pkgs.watchexec,
      packages ? [ ],
      ...
    }@args:
    assert lib.assertMsg (watchers != [ ]) "mkWatchMany: 'watchers' must not be empty";
    let
      taskModuleArgs = builtins.removeAttrs args [
        "name"
        "watchers"
        "package"
        "packages"
      ];

      # Resolve each watcher's package and give it a stable process name.
      indexed = lib.imap0 (i: w: {
        inherit i;
        watcher = w // {
          package = w.package or package;
        };
      }) watchers;

      # Process name: either user-supplied `name`, or `watcher-<index>`.
      processNameOf = { i, watcher }: watcher.name or "watcher-${toString i}";

      processes = lib.listToAttrs (
        map (entry: {
          name = processNameOf entry;
          value = {
            command = mkWatchexecCmd entry.watcher;
            packages = [ entry.watcher.package ];
          };
        }) indexed
      );
    in
    taskModuleArgs
    // {
      raw = true;
      skip = true;
      command =
        (mkProcessTree {
          inherit
            name
            packages
            processes
            ;
        })
        + "/bin/${name}";
    };
in
{
  inherit mkWatch mkWatchMany;
}
