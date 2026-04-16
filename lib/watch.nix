{ lib, pkgs }:

{
  command,
  watch ? [ "." ],
  extensions ? [ ],
  ignore ? [ ],
  debounce ? null,
  clearScreen ? true,
  onStart ? false,
  package ? pkgs.watchexec,
  packages ? [ ],
  env ? { },
  description ? null,
}:

let
  allPackages = [ package ] ++ packages;

  watchexecCmd = lib.concatStringsSep " " (
    lib.filter (s: s != "") (
      [ (lib.getExe package) ]
      ++ map (p: "--watch '${p}'") watch
      ++ lib.optionals (extensions != [ ]) [
        "--exts"
        (lib.concatStringsSep "," extensions)
      ]
      ++ map (p: "--ignore '${p}'") ignore
      ++ lib.optionals (debounce != null) [
        "--debounce"
        (toString debounce)
      ]
      ++ lib.optionals clearScreen [ "--clear" ]
      ++ lib.optionals onStart [
        "--on-busy-update=restart"
        "--watch-when-idle"
      ]
      ++ [
        "--"
        command
      ]
    )
  );
in
{
  inherit description;
  raw = true;
  command = pkgs.writeShellApplication {
    name = "watch";
    runtimeInputs = allPackages;
    runtimeEnv = env;
    text = watchexecCmd;
  };
}
