{
  description = "spglib 2.7.0 packaged from source as a Zig 0.16 SDK, static and shared";

  inputs = {
    # Pinned by revision; `package.nix` has no nixpkgs of its own. The lock file
    # and the recorded hashes are the integration owner's.
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
          # `zig` is passed explicitly so the SDK is built with the pinned 0.16.0
          # attribute rather than with whatever `pkgs.zig` happens to be.
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
          # The SDK's native default is a static linkage.
          default = static;
        });

      # Tools only. Building the SDK is `nix build .#static`, not shell entry;
      # canonical development is `devenv shell`.
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