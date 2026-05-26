{
  description = "up";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    flake-schemas.url = "https://flakehub.com/f/DeterminateSystems/flake-schemas/0";
  };

  outputs =
    { self, ... }@inputs:
    let
      inherit (inputs.nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
              };
              overlays = [ self.overlays.default ];
            };
          }
        );
    in
    {
      lib = import ./lib;

      overlays.default = final: prev: {
        up = (
          import ./lib {
            inherit (final) lib;
            pkgs = final;
          }
        );
      };

      schemas = {
        inherit (inputs.flake-schemas.schemas)
          overlays
          schemas
          ;
      }
      // {
        inherit (self.exportedSchemas) exportedSchemas;
      };

      exportedSchemas =
        let
          mkChildren = children: { inherit children; };
        in
        {
          exportedSchemas = {
            version = 1;
            doc = ''
              The `exportedSchemas` flake output defines flake schemas that you intend for other flakes to use.
            '';

            inventory =
              output:
              mkChildren (
                builtins.mapAttrs (schemaName: schemaDef: {
                  shortDescription = "A schema checker for the `${schemaName}` flake output";
                  evalChecks.isValidSchema =
                    schemaDef.version or 0 == 1
                    && schemaDef ? doc
                    && builtins.isString schemaDef.doc
                    && schemaDef ? inventory
                    && builtins.isFunction schemaDef.inventory;
                  what = "flake schema";
                }) output
              );
          };

          tasks = {
            version = 1;
            doc = ''
              The `tasks` output defines tasks that you can run independently or
            '';
            appendSystem = true;
            roles.nix-run = { };
            defaultAttrPath = [ "default" ];
            inventory =
              output:
              mkChildren (
                builtins.mapAttrs (system: tasks: {
                  forSystems = [ system ];
                  children = builtins.mapAttrs (_name: task: {
                    forSystems = [ system ];
                    evalChecks.isAttrsOrDerivation = builtins.isAttrs task;
                    what = task.description or "runnable task";
                  }) tasks;
                }) output
              );
          };

          taskRunners = {
            version = 1;
            doc = ''
              The `taskRunners` output provides task runner scripts that you can run using `nix run`.
            '';
            roles.nix-run = { };
            appendSystem = true;
            defaultAttrPath = [ "default" ];
            inventory =
              output:
              mkChildren (
                builtins.mapAttrs (system: runners: {
                  forSystems = [ system ];
                  children = builtins.mapAttrs (_name: runner: {
                    forSystems = [ system ];
                    evalChecks.isDerivation = lib.isDerivation runner;
                    children = builtins.mapAttrs (taskName: task: {
                      forSystems = [ system ];
                      what = task.description or "task runner";
                    }) (runner.tasks or { });
                  }) runners;
                }) output
              );
          };

          staticEnvVars = {
            version = 1;
            doc = ''
              The `staticEnvVars` output provides sets of environment variables
              that can be sourced into shells or consumed by other tools.
            '';
            inventory =
              output:
              let
                isEnv = v: builtins.isAttrs v && builtins.all (s: builtins.isString s) (builtins.attrValues v);
              in
              mkChildren (
                builtins.mapAttrs (_name: env: {
                  evalChecks.isAttrs = builtins.isAttrs env;
                  evalChecks.allStrings = isEnv env;
                  what = "static environment variable set";
                }) output
              );
          };

          computedEnvVars = {
            version = 1;
            doc = ''
              The `computedEnvVars` output provides sets of environment variables
              that can be sourced into shells or consumed by other tools. Unlike `staticEnvVars`, these
              sets are system specific and involve some kind of computation (like using packages from Nixpkgs).
            '';
            appendSystem = true;
            inventory =
              output:
              let
                isEnv = v: builtins.isAttrs v && builtins.all (s: builtins.isString s) (builtins.attrValues v);
              in
              mkChildren (
                builtins.mapAttrs (system: envs: {
                  forSystems = [ system ];
                  children = builtins.mapAttrs (_name: env: {
                    forSystems = [ system ];
                    evalChecks.isAttrs = builtins.isAttrs env;
                    evalChecks.allStrings = isEnv env;
                    what = "computed environment variable set";
                  }) envs;
                }) output
              );
          };

          processes = {
            version = 1;
            doc = ''
              The `processes` flake output contains declaratively defined long-running
              processes that can be orchestrated by a process tree. Each
              process is evaluated through the process module and exposes a generated
              `script` derivation and `bin` path.
            '';
            inventory = output: {
              children = builtins.mapAttrs (system: procs: {
                forSystems = [ system ];
                children = builtins.mapAttrs (procName: proc: {
                  forSystems = [ system ];
                  shortDescription = if proc.description == null then "" else proc.description;
                  what = "process";
                  derivation = proc.script;
                }) procs;
              }) output;
            };
          };

          processTrees = {
            version = 1;
            doc = ''
              The `processTrees` output provides process-compose configurations that you can run using `nix run`.
            '';
            roles.nix-run = { };
            appendSystem = true;
            defaultAttrPath = [ "default" ];
            inventory =
              output:
              mkChildren (
                builtins.mapAttrs (system: trees: {
                  forSystems = [ system ];
                  children = builtins.mapAttrs (_name: tree: {
                    forSystems = [ system ];
                    evalChecks.isDerivation = lib.isDerivation tree;
                    children = builtins.mapAttrs (procName: proc: {
                      forSystems = [ system ];
                      what = if proc.description != null then proc.description else "process";
                      shortDescription = if proc.command != null then proc.command else "";
                    }) (tree.processes or { });
                  }) trees;
                }) output
              );
          };
        };
    };
}
