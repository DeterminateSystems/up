{ lib, pkgs }:

{
  version ? null,
  gofmt ? true,
  gopls ? false,
  gotools ? false,
  golangci-lint ? false,
}:

let
  goPkg =
    if version == null then
      pkgs.go
    else
      pkgs.${"go_${builtins.replaceStrings [ "." ] [ "_" ] (toString version)}"}
        or (throw "unknown go version: ${version}");

  optionalTools =
    lib.optionals gopls [ pkgs.gopls ]
    ++ lib.optionals gotools [ pkgs.gotools ]
    ++ lib.optionals golangci-lint [ pkgs.golangci-lint ];
in
{
  packages = pkgs.symlinkJoin {
    name = "go-toolchain";
    paths = [ goPkg ];
  };
}
