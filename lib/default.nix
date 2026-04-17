{ lib, pkgs }:

let
  mkScript =
    {
      name,
      command,
      environment ? { },
      packages ? [ ],
      excludeShellChecks ? [ ],
    }:
    let
      toEnvAttrs =
        env:
        if builtins.isAttrs env then
          env
        else
          lib.listToAttrs (
            map (
              s:
              let
                parts = lib.splitString "=" s;
              in
              {
                name = builtins.head parts;
                value = lib.concatStringsSep "=" (builtins.tail parts);
              }
            ) env
          );

      envAttrs = toEnvAttrs environment;
      exports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") envAttrs
      );
    in
    pkgs.writeShellApplication {
      inherit name excludeShellChecks;
      runtimeInputs = packages;
      text = lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          exports
          command
        ]
      );
    };

  taskModule = import ./task.nix { inherit lib mkScript pkgs; };
in
{
  mkBenchmarkTask = import ./benchmark.nix {
    inherit
      lib
      pkgs
      taskModule
      ;
  };

  mkTaskRunner = import ./task-runner.nix {
    inherit
      lib
      mkScript
      pkgs
      taskModule
      ;
  };

  mkProcessTree = import ./process-tree.nix {
    inherit
      lib
      mkScript
      pkgs
      taskModule
      ;
  };

  mkWatch = import ./watch.nix { inherit lib mkScript pkgs; };

  mkTool = import ./tool.nix { inherit lib mkScript pkgs; };
}
