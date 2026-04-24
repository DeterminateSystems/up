{ lib, pkgs }:

let
  mkEnv =
    environment:
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
      isStatic = v: !(lib.hasInfix "$" v);
      dynamicEnv = lib.filterAttrs (_: v: !isStatic v) envAttrs;
      escapeForDoubleQuotes = v: lib.replaceStrings [ "\\" "\"" "`" "!" ] [ "\\\\" "\\\"" "\\`" "\\!" ] v;
    in
    {
      static = lib.filterAttrs (_: isStatic) envAttrs;
      exports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''export ${k}="${escapeForDoubleQuotes v}"'') dynamicEnv
      );
    };

  mkScript =
    {
      name,
      command,
      environment ? { },
      packages ? [ ],
      excludeShellChecks ? [ ],
    }:
    let
      inherit (mkEnv environment) static exports;
    in
    pkgs.writeShellApplication {
      inherit name excludeShellChecks;
      runtimeInputs = packages;
      runtimeEnv = static;
      text = lib.concatStringsSep "\n\n" (lib.optionals (exports != "") [ exports ] ++ [ command ]);
    };

  processModule = import ./process.nix {
    inherit lib mkScript pkgs;
  };

  taskModule = import ./task.nix { inherit lib mkScript pkgs; };

  mkProcessTree = import ./process-tree.nix {
    inherit
      lib
      mkScript
      pkgs
      processModule
      taskModule
      ;
  };
in
{
  inherit mkProcessTree;

  mkBenchmarkTask = import ./benchmark.nix {
    inherit
      lib
      pkgs
      taskModule
      ;
  };

  mkProcess =
    args:
    (lib.evalModules {
      modules = [
        processModule
        args
      ];
    }).config;

  mkTaskRunner = import ./task-runner.nix {
    inherit
      lib
      mkScript
      pkgs
      taskModule
      ;
  };

  mkTool = import ./tool.nix { inherit lib mkScript pkgs; };

  inherit (import ./watch.nix { inherit lib mkProcessTree pkgs; }) mkWatch mkWatchMany;
}
