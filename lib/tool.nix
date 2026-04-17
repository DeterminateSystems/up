{
  lib,
  mkScript,
  pkgs,
}:

{
  name,
  package ? null,
  packages ? [ ],
  args ? [ ],
  env ? { },
}:

assert lib.assertMsg (
  package != null || packages != [ ]
) "mkTool: '${name}' must specify either 'package' or 'packages'";

let
  allPackages = lib.optional (package != null) package ++ packages;
in
mkScript {
  inherit name;
  packages = allPackages;
  environment = env;
  command = lib.concatStringsSep " " ([ (lib.getExe (builtins.head allPackages)) ] ++ args);
}
