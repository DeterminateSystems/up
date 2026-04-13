{ lib, pkgs }:

{
  nodejs ? false,
  bun ? false,
  npm ? false,
  pnpm ? false,
}:

{
  packages = pkgs.symlinkJoin {
    name = "js-env";
    paths =
      lib.optional nodejs pkgs.nodejs
      ++ lib.optional bun pkgs.bun
      ++ lib.optional npm pkgs.npm
      ++ lib.optional pnpm pkgs.pnpm;
  };
}
