{
  lib,
  mkScript,
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
  environment ? { },
  description ? null,
  excludeShellChecks ? [ ],
}:

assert lib.assertMsg (paths != [ ]) "mkWatch: 'paths' must not be empty";

let
  allPackages = [ package ] ++ packages;

  watchexecCmd = lib.concatStringsSep " " (
    [ (lib.getExe package) ]
    ++ map (p: "--watch '${p}'") paths
    ++ lib.optionals (extensions != [ ]) [
      "--exts"
      (lib.concatStringsSep "," extensions)
    ]
    ++ map (p: "--ignore '${p}'") ignore
    ++ lib.optionals (debounce != null) [
      "--debounce"
      (toString debounce)
    ]
    ++ [
      "--"
      command
    ]
  );
in
{
  inherit description;
  raw = true;
  command = mkScript {
    name = "watch";
    inherit environment excludeShellChecks;
    packages = allPackages;
    command = watchexecCmd;
  };
}
