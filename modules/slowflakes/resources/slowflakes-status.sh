#!/usr/bin/env bash
set -euo pipefail

# environment variables declarations should be prepended in scripts.nix, as it will have the context of the options
#
#    # Inject module options as environment variables, followed by the script body
#    text = ''
#      export CONFIGURED_REPO_PATH="${cfg.repoPath}"
#      export TARGET_STATE_DIR="${cfg.stateFolderName}"
#      export DELAY_DAYS="${toString cfg.delayDays}"
#    '' + builtins.readFile ./resources/${name}.sh;



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