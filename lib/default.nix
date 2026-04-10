{ lib, pkgs }:

let
  taskModule = import ./task.nix { inherit lib pkgs; };
in
{
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

  mkTask =
    args:
    (lib.evalModules {
      modules = [
        taskModule
        { config._module.args.name = args.name or "task"; }
        args
      ];
    }).config.drv;
}
