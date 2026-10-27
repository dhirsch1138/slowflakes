{ config, lib, pkgs, ... }:

let
  cfg = config.services.slowflakes;
  stateDir = "/var/lib/${cfg.stateFolderName}";  

  # Helper function to convert booleans to string for bash consumption
  boolToString = b: if b then "true" else "false";

  # Create a shell application derivation for the background automation task
  automationScript = pkgs.writeShellApplication {
    name = "slowflakes-automation";

    # Inject all configuration options as environment variables, then append the script body
    text = ''
      export REPO_PATH="${cfg.repoPath}"
      export STATE_FOLDER_NAME="${cfg.stateFolderName}"
      export DELAY_DAYS="${toString cfg.delayDays}"
      export NETWORK_CHECK_ENABLED="${boolToString cfg.networkCheckEnabled}"
      export GIT_USER_NAME="${cfg.gitUserName}"
      export GIT_USER_EMAIL="${cfg.gitUserEmail}"
    '' + builtins.readFile ./resources/scripts/slowflakes-automation.sh;

    # Declare runtime commands used by your automation script
    runtimeInputs = with pkgs; [
      git
      iputils   # for ping
      coreutils
      gnugrep
      nix
    ];
  };
in {
  config = lib.mkIf cfg.enable {
    nix.settings.allowed-users = [ "slowflakes-bot" ];

    users.users.slowflakes-bot = {
      isSystemUser = true;
      group = "slowflakes-bot";
      description = "System user for slowflakes-bot background repository automation";
      home = stateDir;
    };
    users.groups.slowflakes-bot = {};

    systemd.services.slowflakes-localrepo-update = lib.mkIf cfg.enableLocalAutomation {
      description = "Automated daily update for isolated delayed flake state repo";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.git pkgs.nix pkgs.iputils ];

      serviceConfig = {
        # Reference the local automationScript derivation directly:
        ExecStart = "${automationScript}/bin/slowflakes-automation";
        Type = "oneshot";
        RemainAfterExit = true;
        User = "slowflakes-bot";
        Group = "slowflakes-bot";
        StateDirectory = cfg.stateFolderName;
        StateDirectoryMode = "0755";
        PrivateDevices = true;

        # Hardening directives
        ProtectSystem = "strict";
        ReadOnlyPaths = [ cfg.repoPath ];
        ReadWritePaths = [ stateDir ];
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
      };
    };

    systemd.timers.slowflakes-localrepo-update = lib.mkIf cfg.enableLocalAutomation {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}