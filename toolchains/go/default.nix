{ pkgs }:

{
  version ? null,
}:

{
  packages =
    if version == null then
      pkgs.go
    else
      pkgs.${"go_1_${builtins.replaceStrings [ "." ] [ "_" ] (toString version)}"};
}
