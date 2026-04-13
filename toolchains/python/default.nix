{ lib, pkgs }:

{
  version ? null,
  uv ? false,
  venv ? {
    enable = false;
    requirements = "";
  },
}:

let
  pythonPkg =
    if version == null then
      pkgs.python3
    else
      pkgs.${"python${builtins.replaceStrings [ "." ] [ "" ] version}"}
        or (throw "unknown python version: ${version}");
in
{
  packages = pkgs.symlinkJoin {
    name = "python-env";
    paths = [ pythonPkg ] ++ lib.optional uv pkgs.uv;
  };

  shellHook = lib.optionalString (venv.enable or false) ''
    uv venv .venv
    ${lib.optionalString (venv.requirements or "" != "") ''
      uv pip install ${venv.requirements}
    ''}
  '';
}
