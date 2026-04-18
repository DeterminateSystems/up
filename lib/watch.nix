{
  lib,
  pkgs,
}:

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

assert lib.assertMsg (paths != [ ]) "mkWatch: 'paths' must not be empty";

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

  watchexecPrefix = lib.escapeShellArgs (
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
  watchexecCmd = "${watchexecPrefix} ${command}";
in
taskModuleArgs
// {
  raw = true;
  packages = packages ++ [ package ];
  command = watchexecCmd;
}
