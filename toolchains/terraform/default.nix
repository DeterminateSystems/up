{ pkgs }:

{
  plugins ? [ ],
}:

let
  tfPkg = pkgs.terraform;
in
{
  packages = if plugins == [ ] then tfPkg else tfPkg.withPlugins (p: map (name: p.${name}) plugins);
  shellHook = "";
  env = {
    TF_CLI_ARGS = "-no-color";
  };
}
