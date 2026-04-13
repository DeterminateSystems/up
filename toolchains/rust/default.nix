{
  fenix,
  lib,
  system,
}:

{
  stable ? true,
  channel ? null,
  targets ? [ ],
  envSrcPath ? false,
}:
let
  fenixPkgs = fenix.packages.${system};

  rustToolchain =
    (
      if channel != null then
        {
          "stable" = fenixPkgs.stable;
          "nightly" = fenixPkgs.latest;
          "beta" = fenixPkgs.beta;
        }
        .${channel} or (throw "unknown rust channel: ${channel}")
      else if stable then
        fenixPkgs.stable
      else
        fenixPkgs.latest
    ).toolchain;

  targetStdlibs = map (target: fenixPkgs.targets.${target}.stable.rust-std) targets;

  packages = fenixPkgs.combine ([ rustToolchain ] ++ targetStdlibs);
in
{
  env = lib.optionalAttrs envSrcPath {
    RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
  };

  inherit packages;
}
