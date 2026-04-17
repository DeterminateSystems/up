{
  lib,
  mkScript,
  pkgs,
}:

{
  name,
  tool ? null,
  args ? [ ],
  environment ? { },
}:

assert lib.assertMsg (tool != null) "mkTool: '${name}' must specify a 'tool'";

mkScript {
  inherit environment name;
  packages = [ tool ];
  command = lib.escapeShellArgs ([ (lib.getExe tool) ] ++ args);
}
