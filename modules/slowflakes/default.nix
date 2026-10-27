{ config, lib, pkgs, ... }:

let
  cfg = config.services.slowflakes;
  stateDir = "/var/lib/${cfg.stateFolderName}";

  scripts = import ./scripts.nix { inherit pkgs config; };
  manPages = import ./manpages.nix { inherit pkgs; };
  automation = import ./automation.nix { inherit config lib pkgs; };
in {
  imports = [
    automation
  ];

  options.services.slowflakes = {
    enable = lib.mkEnableOption "slowflakes isolated delayed flake.lock workflow helper";

    delayDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Number of days to delay flake.lock updates.";
    };

    stateFolderName = lib.mkOption {
      type = lib.types.str;
      default = "slowflakes-state";
      description = "Name of the state directory created under /var/lib/ to store the isolated Git repository.";
    };

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "Absolute path to the primary configuration repository.";
    };

    enableLocalAutomation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable a systemd service to daily update the isolated rolling state repo.";
    };

    networkCheckEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable pre-flight network reachability check before running background flake updates.";
    };

    gitUserName = lib.mkOption {
      type = lib.types.str;
      default = "Slowflakes Bot";
      description = "Git user name to use inside the isolated state repo.";
    };

    gitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = "slowflakes-bot@localhost";
      description = "Git user email to use inside the isolated state repo.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      scripts.slowflakesUpdateScript
      scripts.slowflakesStatusScript
      scripts.slowflakesCleanupScript
      manPages.slowflakesManPagesPackage
    ];
  };
}
