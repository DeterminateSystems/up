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
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowBroken = true;
                allowUnfree = true;
              };
              overlays = [ self.overlays.default ];
            };
          }
        );
    in
    {
      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt);

      lib = import ./lib;

      overlays.default = final: prev: {
        lib =
          prev.lib
          // self.lib {
            inherit (prev) lib;
            pkgs = prev;
          };
      };

      schemas = {
        inherit (inputs.flake-schemas.schemas)
          formatter
          overlays
          schemas
          ;
      }
      // {
        taskRunners = {
          version = 1;
          doc = ''
            The `taskRunners` output provides a CLI task runner with shell completions.
          '';
          appendSystem = true;
          defaultAttrPath = [ "default" ];
          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: runners: {
                forSystems = [ system ];
                children = builtins.mapAttrs (_name: runner: {
                  forSystems = [ system ];
                  evalChecks.isDerivation = lib.isDerivation runner;
                  what = runner.description or "task runner";
                }) runners;
              }) output
            );
        };

        envVars = {
          version = 1;
          doc = ''
            The `envVars` output provides sets of environment variables
            that can be sourced into shells or consumed by other tools.
          '';
          inventory =
            output:
            let
              isEnv = v: builtins.isAttrs v && builtins.all (s: builtins.isString s) (builtins.attrValues v);
              isPerSystem = builtins.all (v: builtins.isAttrs v && !isEnv v) (builtins.attrValues output);
            in
            inputs.flake-schemas.lib.mkChildren (
              if isPerSystem then
                builtins.mapAttrs (system: envs: {
                  forSystems = [ system ];
                  children = builtins.mapAttrs (_name: env: {
                    forSystems = [ system ];
                    evalChecks.isAttrs = builtins.isAttrs env;
                    evalChecks.allStrings = isEnv env;
                    what = "environment variable set";
                  }) envs;
                }) output
              else
                builtins.mapAttrs (_name: env: {
                  evalChecks.isAttrs = builtins.isAttrs env;
                  evalChecks.allStrings = isEnv env;
                  what = "environment variables set";
                }) output
            );
        };

        tasks = {
          version = 1;
          doc = ''
            The `tasks` output provides one-shot runnable commands such as database migrations, seed scripts, and build steps.
          '';
          roles.nix-run = { };
          appendSystem = true;
          inventory =
            output:
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: tasks: {
                forSystems = [ system ];
                children = builtins.mapAttrs (taskName: task: {
                  forSystems = [ system ];
                  evalChecks = {
                    hasCommand = task ? command || task ? packages;
                    isAttrs = builtins.isAttrs task;
                  };
                  what = task.description or "task";
                }) tasks;
              }) output
            );
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
            inputs.flake-schemas.lib.mkChildren (
              builtins.mapAttrs (system: trees: {
                forSystems = [ system ];
                children = builtins.mapAttrs (_name: tree: {
                  forSystems = [ system ];
                  evalChecks.isDerivation = lib.isDerivation tree;
                  what = tree.description or "process tree";
                }) trees;
              }) output
            );
        };
      };
    };
}
