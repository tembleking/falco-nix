{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      utils,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        falco = pkgs.callPackage ./falco.nix { };
      in
      {
        packages = {
          inherit falco;
          default = falco;
        };
        devShells.default =
          with pkgs;
          mkShell {
            buildInputs = [
              # Add here dependencies for the project.
              cmake
              cmake-language-server
            ];
          };

        formatter = pkgs.alejandra;
      }
    );
}
