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
    attrs:
    (lib.evalModules {
      modules = [
        taskModule
        { config = attrs; }
      ];
    }).config.drv;
}
