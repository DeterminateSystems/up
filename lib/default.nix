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
    let
      result =
        (lib.evalModules {
          modules = [
            taskModule
            { config._module.args.name = args.name or "task"; }
            args
          ];
        }).config;
    in
    {
      __isTask = true;

      inherit (result)
        drv
        bin
        command
        packages
        description
        environment
        before
        after
        status
        ;
    };
}
