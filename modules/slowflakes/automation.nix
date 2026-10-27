{ config, lib, pkgs, ... }:

let
  cfg = config.services.slowflakes;
  stateDir = "/var/lib/${cfg.stateFolderName}";  
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

    # get the automation script(s), we are doing it this way so that we
    # don't have to make them globally accessible packages, we want it local to this service
    automation = import ./automation.nix { inherit pkgs config; };

    systemd.services.slowflakes-localrepo-update = lib.mkIf cfg.enableLocalAutomation {
      description = "Automated daily update for isolated delayed flake state repo";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.git pkgs.nix pkgs.iputils ];

      serviceConfig = {
        # Invoke the robust, shellcheck-validated script wrapper directly:
        ExecStart = "${automation.automationScript}/bin/slowflakes-automation";
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
