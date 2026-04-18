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

      isStatic = v: !(lib.hasInfix "$" v);
      staticEnv = lib.filterAttrs (_: isStatic) envAttrs;
      dynamicEnv = lib.filterAttrs (_: v: !isStatic v) envAttrs;

      escapeForDoubleQuotes = v: lib.replaceStrings [ "\\" "\"" "`" "!" ] [ "\\\\" "\\\"" "\\`" "\\!" ] v;

      dynamicExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: ''export ${k}="${escapeForDoubleQuotes v}"'') dynamicEnv
      );
    in
    pkgs.writeShellApplication {
      inherit name excludeShellChecks;
      runtimeInputs = packages;
      runtimeEnv = staticEnv;

      text = lib.concatStringsSep "\n\n" (
        lib.optionals (dynamicEnv != { }) [ dynamicExports ] ++ [ command ]
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

  mkWatch = import ./watch.nix { inherit lib pkgs; };

  mkTool = import ./tool.nix { inherit lib mkScript pkgs; };
}
