{ pkgs, cfg, stateDir, ... }:

let
  slowflakesUpdateScript = pkgs.writeShellApplication {
    name = "slowflakes-update";
    runtimeInputs = [ pkgs.git pkgs.gnused ];
    text = ''
      set -euo pipefail

      TARGET_STATE_DIR="${stateDir}"
      CONFIGURED_REPO_PATH="${cfg.repoPath}"
      CURRENT_DIR=$(pwd -P)
      REAL_REPO_PATH=$(cd "$CONFIGURED_REPO_PATH" 2>/dev/null && pwd -P || echo "$CONFIGURED_REPO_PATH")

      if [ "$CURRENT_DIR" != "$REAL_REPO_PATH" ]; then
        echo "Error: 'slowflakes-update' must be executed within the configured repoPath directory ($CONFIGURED_REPO_PATH)." >&2
        echo "Current directory: $CURRENT_DIR" >&2
        exit 1
      fi

      if [ ! -d "$TARGET_STATE_DIR/.git" ]; then
        echo "Error: Isolated state repository not found at $TARGET_STATE_DIR." >&2
        echo "Ensure 'services.slowflakes.enable' is enabled and background timer has initialized state." >&2
        exit 1
      fi

      DELAY_DAYS="''${1:-${toString cfg.delayDays}}"
      echo "Fetching historical lock from isolated state repository..."

      # Uncommitted changes guard
      if ! git diff --quiet flake.lock 2>/dev/null; then
        echo "Warning: 'flake.lock' has uncommitted local modifications in your working directory." >&2
        echo "Aborting to prevent overwriting your uncommitted changes." >&2
        exit 1
      fi

      COMMIT_HASH=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list -n 1 --before="''${DELAY_DAYS} days ago" HEAD 2>/dev/null || true)

      if [ -z "$COMMIT_HASH" ]; then
        echo "Error: No commit found in state repo older than $DELAY_DAYS days." >&2
        exit 1
      fi

      TARGET_DATE_STR=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" log -1 --format="%ci (%h)" "$COMMIT_HASH")
      TARGET_DATE=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" log -1 --format="%ct" "$COMMIT_HASH")

      # Staleness Alert Guard (skip for 0-day delay checks)
      NOW=$(date +%s)
      AGE_SECONDS=$(( NOW - TARGET_DATE ))
      THRESHOLD_SECONDS=$(( DELAY_DAYS * 86400 ))

      if [ "$DELAY_DAYS" -gt 0 ] && [ "$AGE_SECONDS" -ge "$THRESHOLD_SECONDS" ]; then
        echo ""
        echo "################################################################################"
        echo "WARNING: STALENESS ALERT! No new updates have been committed to the isolated"
        echo "state repository in the last $DELAY_DAYS days (or longer)!"
        echo "The newest available snapshot is older than your configured delay threshold."
        echo "Check your background systemd timer ('slowflakes-localrepo-update.service') or network status."
        echo "################################################################################"
        echo ""
      fi

      # Hybrid Local Lock Timestamp Comparison
      LOCAL_COMMIT_DATE=$(git log -1 --format="%ct" -- flake.lock 2>/dev/null || echo "0")
      LOCAL_FILE_MTIME=$(date -r flake.lock +%s 2>/dev/null || echo "0")

      if [ "$LOCAL_FILE_MTIME" -gt "$LOCAL_COMMIT_DATE" ]; then
        LOCAL_LOCK_DATE="$LOCAL_FILE_MTIME"
      else
        LOCAL_LOCK_DATE="$LOCAL_COMMIT_DATE"
      fi

      if [ "$TARGET_DATE" -le "$LOCAL_LOCK_DATE" ]; then
        echo "Warning: The selected $DELAY_DAYS-day-old lock is older than or equal to your current local flake.lock modification." >&2
        echo "Aborting to prevent overwriting your newer lockfile." >&2
        exit 1
      fi

      echo "Found qualifying lock from state repo: $TARGET_DATE_STR"
      git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" show "$COMMIT_HASH:flake.lock" > ./flake.lock
      echo "Success: Updated flake.lock in working directory from isolated history. Ready to review or rebuild!"
    '';
  };

  slowflakesStatusScript = pkgs.writeShellApplication {
    name = "slowflakes-status";
    runtimeInputs = [ pkgs.git pkgs.systemd pkgs.coreutils ];
    text = ''
      set -euo pipefail

      TARGET_STATE_DIR="${stateDir}"
      CONFIGURED_REPO_PATH="${cfg.repoPath}"

      echo "=== Slowflakes Diagnostic Status ==="
      echo "State Directory:  $TARGET_STATE_DIR ($(du -sh "$TARGET_STATE_DIR" 2>/dev/null | cut -f1 || echo "N/A"))"
      echo "Local Repository: $CONFIGURED_REPO_PATH"

      echo ""
      echo "--- Systemd Automation Status ---"
      if systemctl is-active --quiet slowflakes-localrepo-update.timer 2>/dev/null; then
        echo "Timer Status:      Active (running)"
      elif systemctl is-enabled --quiet slowflakes-localrepo-update.timer 2>/dev/null; then
        echo "Timer Status:      Enabled (inactive)"
      else
        echo "Timer Status:      Disabled / Not installed"
      fi

      LAST_RUN=$(systemctl show slowflakes-localrepo-update.service --property=ExecMainExitTimestamp --value 2>/dev/null || echo "N/A")
      LAST_RESULT=$(systemctl show slowflakes-localrepo-update.service --property=Result --value 2>/dev/null || echo "N/A")
      NEXT_RUN=$(systemctl show slowflakes-localrepo-update.timer --property=NextElapseUSecReal --value 2>/dev/null || echo "N/A")

      if [ -n "$LAST_RUN" ] && [ "$LAST_RUN" != "N/A" ]; then
        echo "Last Service Run:  $LAST_RUN (Result: $LAST_RESULT)"
      else
        echo "Last Service Run:  Never / Unknown"
      fi

      if [ -n "$NEXT_RUN" ] && [ "$NEXT_RUN" != "N/A" ] && [ "$NEXT_RUN" != "0" ]; then
        echo "Next Scheduled:    $NEXT_RUN"
      fi

      echo ""
      echo "--- Active vs Target Lock Comparison ---"
      if [ -f "$CONFIGURED_REPO_PATH/flake.lock" ]; then
        LOCAL_MOD=$(date -r "$CONFIGURED_REPO_PATH/flake.lock" "+%Y-%m-%d %H:%M:%S %z" 2>/dev/null || echo "Unknown")
        if ! git -C "$CONFIGURED_REPO_PATH" diff --quiet flake.lock 2>/dev/null; then
          echo "Local flake.lock:  Modified $LOCAL_MOD [Uncommitted Edits]"
        else
          echo "Local flake.lock:  Modified $LOCAL_MOD [Committed]"
        fi
      else
        echo "Local flake.lock:  Missing"
      fi

      if [ -d "$TARGET_STATE_DIR/.git" ]; then
        DELAY_DAYS="${toString cfg.delayDays}"
        COMMIT_HASH=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list -n 1 --before="''${DELAY_DAYS} days ago" HEAD 2>/dev/null || true)
        if [ -n "$COMMIT_HASH" ]; then
          TARGET_DATE_STR=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" log -1 --format="%Y-%m-%d %H:%M:%S %z (%h)" "$COMMIT_HASH")
          echo "$DELAY_DAYS-Day Target Lock: Available -> $TARGET_DATE_STR"
        else
          echo "$DELAY_DAYS-Day Target Lock: None available yet (state history spans less than $DELAY_DAYS days)"
        fi
      fi

      echo ""
      echo "--- State Repository History ---"
      if [ ! -d "$TARGET_STATE_DIR/.git" ]; then
        echo "State repository is uninitialized."
        exit 0
      fi

      TOTAL_SNAPSHOTS=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list --count HEAD 2>/dev/null || echo "0")
      OLDEST_COMMIT=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" log --reverse --format="%ci" 2>/dev/null | head -n 1 || echo "N/A")
      LATEST_COMMIT=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" log -1 --format="%ci (%h)" 2>/dev/null || echo "N/A")

      echo "Total Stored Snapshots: $TOTAL_SNAPSHOTS"
      echo "Oldest Snapshot Date:   $OLDEST_COMMIT"
      echo "Latest Snapshot Date:   $LATEST_COMMIT"
      echo ""
      echo "Recent Historical Snapshots:"
      git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" log -n 5 --format="  - [%h] %ad : %s" --date=short 2>/dev/null || echo "  No commits found."
    '';
  };

  slowflakesCleanupScript = pkgs.writeShellApplication {
    name = "slowflakes-cleanup";
    runtimeInputs = [ pkgs.git ];
    text = ''
      set -euo pipefail
      TARGET_STATE_DIR="${stateDir}"

      if [ ! -d "$TARGET_STATE_DIR" ]; then
        echo "State directory $TARGET_STATE_DIR does not exist. Nothing to clean."
        exit 0
      fi

      echo "WARNING: You are about to execute: sudo rm -rf '$TARGET_STATE_DIR'"
      echo "This will completely destroy the isolated rolling state repository and all its update history."
      echo "The background systemd service will re-initialize it fresh on its next run."
      read -rp "Are you sure you want to proceed? [y/N] " response

      case "$response" in
        [yY][eE][sS]|[yY])
          echo "Purging $TARGET_STATE_DIR..."
          sudo rm -rf "$TARGET_STATE_DIR"
          echo "Success: Isolated state repository cleared."
          ;;
        *)
          echo "Aborted."
          exit 0
          ;;
      esac
    '';
  };
in {
  slowflakesUpdateScript = slowflakesUpdateScript;
  slowflakesStatusScript = slowflakesStatusScript;
  slowflakesCleanupScript = slowflakesCleanupScript;

  # Fallback backward-compatibility aliases
  updateScript = slowflakesUpdateScript;
  statusScript = slowflakesStatusScript;
  cleanupScript = slowflakesCleanupScript;
}
