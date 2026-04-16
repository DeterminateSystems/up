{ lib, pkgs }:

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
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = allPackages;
  runtimeEnv = env;
  text = lib.concatStringsSep " " ([ (lib.getExe (builtins.head allPackages)) ] ++ args);
}
