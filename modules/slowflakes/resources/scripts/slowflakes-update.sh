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