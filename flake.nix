{
  description = "spglib 2.7.0 packaged from source as a Zig 0.17 SDK, static and shared";

  inputs = {
    # Pin nixpkgs by revision.
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          # Use the pinned Zig 0.17.0 toolchain.
          static = pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_17;
            linkage = "static";
          };
          shared = pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_17;
            linkage = "dynamic";
          };
        in
        {
          inherit static shared;
          # Default to static, matching `build.zig`.
          default = static;
        });

      # Shell tools only; SDK builds are separate outputs.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.zig_0_17
            pkgs.patch
            pkgs.git
          ];
        };
      });
    };
}