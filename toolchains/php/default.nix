{ lib, pkgs }:

{
  version ? "8.3",
  ini ? "",
  fpm ? {
    pools = { };
  },
}:

let
  phpPkg =
    pkgs.${"php${builtins.replaceStrings [ "." ] [ "" ] version}"}
      or (throw "unknown php version: ${version}");

  fpmConf = pkgs.writeText "php-fpm.conf" (
    lib.concatStrings (
      lib.mapAttrsToList (
        poolName: pool:
        ''
          [${poolName}]
        ''
        + lib.concatStrings (lib.mapAttrsToList (k: v: "${k} = ${v}\n") (pool.settings or { }))
      ) (fpm.pools or { })
    )
  );
in
{
  packages =
    if ini == "" then
      phpPkg
    else
      phpPkg.buildEnv {
        extraConfig = ini;
      };
  shellHook = lib.optionalString (fpm.pools != { }) ''
    php-fpm -y ${fpmConf} -D
    trap "php-fpm -y ${fpmConf} -F -R 2>/dev/null" EXIT
  '';
  env = { };
}
