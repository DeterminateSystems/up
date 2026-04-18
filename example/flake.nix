{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    up = {
      url = "path:..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-schemas.follows = "up/flake-schemas";
  };

  outputs =
    { self, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
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
              overlays = [ inputs.up.overlays.default ];
            };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              self.processTrees.${system}.api
              self.taskRunners.${system}.proto
            ];
          };
        }
      );

      processTrees = forEachSupportedSystem (
        { pkgs, system }:
        {
          api = pkgs.lib.mkProcessTree {
            name = "api";

            processes.hello.command = "sleep 1000";
          };
        }
      );

      taskRunners = forEachSupportedSystem (
        { pkgs, ... }:
        {
          proto = pkgs.lib.mkTaskRunner {
            name = "proto";

            packages = with pkgs; [
              buf
              protobuf
              protoc-gen-prost
              protoc-gen-tonic
            ];

            tasks = {
              build = {
                description = "Build the buf module";
                aliases = [ "b" ];
                after = [
                  "clean"
                  "lint"
                ];
                command = "buf build";
              };
              clean = {
                description = "Start from scratch";
                aliases = [ "c" ];
                command = "rm -rf src/gen";
              };
              format = {
                description = "Format .proto files";
                aliases = [
                  "f"
                  "fmt"
                ];
                command = "buf format --write";
              };
              generate = {
                description = "Generate stubs";
                aliases = [
                  "gen"
                  "g"
                ];
                after = [ "build" ];
                command = "buf generate";
              };
              lint = {
                aliases = [ "l" ];
                command = "buf lint";
              };
              watch-gen =
                pkgs.lib.mkWatch {
                  command = "buf generate";
                  paths = [
                    "proto"
                    "buf.gen.yaml"
                  ];
                  extensions = [
                    "proto"
                    "yaml"
                  ];
                }
                // {
                  description = "Regenerate stubs on .proto change";
                  aliases = [
                    "w"
                    "dev"
                  ];
                };
            };
          };
        }
      );

      schemas = {
        inherit (inputs.flake-schemas.schemas) devShells;
      }
      // {
        inherit (inputs.up.exportedSchemas) processTrees taskRunners;
      };
    };
}
