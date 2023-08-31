{
  description = "Build maven applications with NixOS dependency caching";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          mavenDep = (import ./maven.nix { inherit pkgs; lib = pkgs.lib; });
        in
        {
          default = mavenDep.buildMaven { name = "foo"; version = "1.2"; src = ./.; lockfile = ./lockfile.json; };
        }
      );
    };
}
