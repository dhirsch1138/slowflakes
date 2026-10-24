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

    systemd.services.slowflakes-localrepo-update = lib.mkIf cfg.enableLocalAutomation {
      description = "Automated daily update for isolated delayed flake state repo";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.git pkgs.nix pkgs.iputils ];

      script = ''
        set -euo pipefail
        TARGET_STATE_DIR="${stateDir}"

        echo "Starting slowflakes isolated state update routine..."
        echo "Target state directory: $TARGET_STATE_DIR"

        ${lib.optionalString cfg.networkCheckEnabled ''
        echo "Checking network connectivity before attempting upstream update..."
        if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
          echo "Notice: Network connectivity could not be confirmed (offline or unreachable)."
          echo "Exiting gracefully without failing systemd unit."
          exit 0
        fi
        echo "Network connectivity confirmed."
        ''}

        if [ ! -d "$TARGET_STATE_DIR/.git" ]; then
          echo "Isolated state repository not found. Initializing fresh repository at $TARGET_STATE_DIR..."
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" init -b main
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" config user.name "${cfg.gitUserName}"
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" config user.email "${cfg.gitUserEmail}"
          
          if [ -f "${cfg.repoPath}/flake.nix" ]; then
            echo "Seeding initial baseline flake.nix and flake.lock from ${cfg.repoPath}..."
            cp "${cfg.repoPath}/flake.nix" "$TARGET_STATE_DIR/"
            if [ -f "${cfg.repoPath}/flake.lock" ]; then
              cp "${cfg.repoPath}/flake.lock" "$TARGET_STATE_DIR/"
            fi
            git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" add flake.nix flake.lock 2>/dev/null || true
            git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" commit -m "Initial baseline seed" 2>/dev/null || true
          fi
        fi

        echo "Pulling latest flake inputs into isolated state repo..."
        nix --extra-experimental-features "nix-command flakes" flake update --flake "$TARGET_STATE_DIR"

        if git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" diff --quiet flake.lock; then
          echo "No upstream flake.lock changes detected. State is up to date."
        else
          TODAY=$(date "+%Y-%m-%d")
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" add flake.lock
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" commit -m "chore(flake): automated state update $TODAY"
          echo "Success: New snapshot committed to isolated state repo for $TODAY."
        fi

        # History Retention Pruning Rule
        RETENTION_DAYS=$(( ${toString cfg.delayDays} * 3 ))
        CUTOFF_COMMIT=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list -n 1 --before="''${RETENTION_DAYS} days ago" HEAD 2>/dev/null || true)

        if [ -n "$CUTOFF_COMMIT" ]; then
          COMMIT_COUNT=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list --count "$CUTOFF_COMMIT..HEAD")
          if [ "$COMMIT_COUNT" -gt 5 ]; then
            echo "Pruning historical commits older than $RETENTION_DAYS days (preserving baseline fallback)..."
            git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" reflog expire --expire=now --all || true
            git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" gc --prune=now --aggressive || true
          fi
        fi
      '';

      serviceConfig = {
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
