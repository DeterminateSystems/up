{ lib, pkgs }:

let
  taskModule = import ./task.nix { inherit lib pkgs; };
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
      pkgs
      taskModule
      ;
  };

  mkProcessTree = import ./process-tree.nix {
    inherit
      lib
      pkgs
      taskModule
      ;
  };
}
