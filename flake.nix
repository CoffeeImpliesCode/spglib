{
  description = "spglib 2.7.0 packaged from source as a Zig 0.16 SDK, static and shared";

  inputs = {
    # Pin nixpkgs by revision.
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
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
          # Use the pinned Zig 0.16.0 toolchain.
          static = pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_16;
            linkage = "static";
          };
          shared = pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_16;
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
            pkgs.zig_0_16
            pkgs.patch
            pkgs.git
          ];
        };
      });
    };
}