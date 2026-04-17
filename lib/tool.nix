{
  lib,
  mkScript,
  pkgs,
}:

{
  name,
  tool,
  args ? [ ],
  environment ? { },
}:

mkScript {
  inherit environment name;
  packages = [ tool ];
  command = ''exec ${lib.escapeShellArgs ([ (lib.getExe tool) ] ++ args)} "$@"'';
}
