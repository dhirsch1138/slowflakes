{
  description = "Slowflakes: Isolated delayed flake.lock update buffer for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # Export the NixOS module for external consumption
      nixosModules.default = ./modules/slowflakes;
      nixosModules.slowflakes = self.nixosModules.default;

      # Standalone script packages and man pages for direct building/testing
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cfg = {
            delayDays = 7;
            stateFolderName = "slowflakes-state";
            repoPath = "/etc/nixos";
          };
          stateDir = "/var/lib/${cfg.stateFolderName}";
          scripts = import ./modules/slowflakes/scripts.nix { inherit pkgs cfg stateDir; };
          manPages = import ./modules/slowflakes/manpages.nix { inherit pkgs; };
        in
        {
          update = scripts.slowflakesUpdateScript;
          status = scripts.slowflakesStatusScript;
          cleanup = scripts.slowflakesCleanupScript;
          manpages = manPages.slowflakesManPagesPackage;
        }
      );
    };
}
