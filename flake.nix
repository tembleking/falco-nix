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
    let
      falcoForLinuxPackages = pkgs: lp: pkgs.callPackage ./falco.nix { linuxPackages = pkgs.${lp}; };

      allLinuxPackagesInPkgs =
        pkgs: (builtins.filter (name: pkgs.lib.hasPrefix "linuxPackages" name) (builtins.attrNames pkgs));
      falcoForAllLinuxPackages =
        pkgs:
        pkgs.lib.genAttrs (allLinuxPackagesInPkgs pkgs) (
          lp:
          pkgs.${lp}
          // {
            falco = falcoForLinuxPackages pkgs lp;
          }
        );

      overlays.default =
        final: prev:
        (
          {
            falco = prev.callPackage ./falco.nix { };
          }
          // (falcoForAllLinuxPackages prev)
        );

      flake = utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ self.overlays.default ];
          };
        in
        {
          packages = with pkgs; {
            inherit falco;
            default = falco;
          };

          devShells.default =
            with pkgs;
            mkShell {
              packages = [
                # Add here dependencies for the project.
                cmake-language-server
              ];
              inputsFrom = [ falco ];
            };

          formatter = pkgs.nixfmt-rfc-style;
        }
      );
    in
    flake // { inherit overlays; };
}
