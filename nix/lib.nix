{ lib, pkgs }:

let
  taskModule = import ./task.nix { inherit lib pkgs; };
in
{
  mkTaskRunner = import ./runner.nix {
    inherit
      lib
      pkgs
      taskModule
      ;
  };
  mkProcessTree = import ./processes.nix {
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
