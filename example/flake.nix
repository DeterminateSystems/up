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
              self.processTrees.${system}.dev
              self.taskRunners.${system}.proto
            ];
          };
        }
      );

      processTrees = forEachSupportedSystem (
        { pkgs, system }:
        {
          dev = pkgs.lib.mkProcessTree {
            name = "dev";

            packages = with pkgs; [
              cargo
              rustc
              grpcurl
            ];

            processes = {
              build.command = "cargo build --release";

              service = {
                description = "Run greeter service";
                command = "cargo run";
                readiness_probe = {
                  exec.command = "grpcurl -plaintext localhost:50051 list";
                  period_seconds = 2;
                };
                depends_on.build.condition = "process_completed_successfully";
                watch.paths = [
                  "src"
                  "proto"
                  "Cargo.toml"
                ];
              };

              probe = {
                command = ''
                  grpcurl -plaintext -d '{"name":"world"}' \
                    localhost:50051 greeter.v1.GreeterService/SayHello
                '';
                depends_on.service.condition = "process_healthy";
              };
            };
          };
        }
      );

      taskRunners = forEachSupportedSystem (
        { pkgs, ... }:
        {
          proto = pkgs.lib.mkTaskRunner {
            name = "pr";

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
                description = "Lint Protobuf sources";
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
