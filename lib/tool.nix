{
  lib,
  mkScript,
  pkgs,
}:

{
  name,
  tool,
  args ? [ ],
  packages ? [ ],
  environment ? { },
}:

mkScript {
  inherit environment name;
  packages = [ tool ] ++ packages;
  command = ''exec ${lib.escapeShellArgs ([ (lib.getExe tool) ] ++ args)} "$@"'';
}
