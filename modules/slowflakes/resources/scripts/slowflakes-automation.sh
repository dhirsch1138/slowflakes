       set -euo pipefail
 # Environment variables declarations should be prepended in automationScripts.nix, as it will have the context of the options
 #   # Inject all configuration options as environment variables, then append the script body
 #   text = ''
 #     export REPO_PATH="${cfg.repoPath}"
 #     export STATE_FOLDER_NAME="${cfg.stateFolderName}"
 #     export DELAY_DAYS="${toString cfg.delayDays}"
 #     export NETWORK_CHECK_ENABLED="${boolToString cfg.networkCheckEnabled}"
 #     export GIT_USER_NAME="${cfg.gitUserName}"
 #     export GIT_USER_EMAIL="${cfg.gitUserEmail}"
 #   '' + builtins.readFile ./resources/scripts/slowflakes-automation.sh;
TARGET_STATE_DIR="/var/lib/${STATE_FOLDER_NAME}"
TARGET_REPO="${REPO_PATH}"

echo "Starting slowflakes isolated state update routine..."
echo "Target state directory: $TARGET_STATE_DIR"

# If network check is enabled, verify connectivity first
if [ "${NETWORK_CHECK_ENABLED}" = "true" ]; then
    if ! ping -c 1 8.8.8.8 &>/dev/null && ! ping -c 1 1.1.1.1 &>/dev/null; then
        echo "Network check enabled, but no internet connection detected. Exiting gracefully."
        exit 0
    fi
fi

        if [ ! -d "$TARGET_STATE_DIR/.git" ]; then
          echo "Isolated state repository not found. Initializing fresh repository at $TARGET_STATE_DIR..."
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" init -b main
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" config user.name "$GIT_USER_NAME"
          git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" config user.email "$GIT_USER_EMAIL"
          
          if [ -f "$TARGET_REPO/flake.nix" ]; then
            echo "Seeding initial baseline flake.nix and flake.lock from $TARGET_REPO..."
            cp "$TARGET_REPO/flake.nix" "$TARGET_STATE_DIR/"
            if [ -f "$TARGET_REPO/flake.lock" ]; then
              cp "$TARGET_REPO/flake.lock" "$TARGET_STATE_DIR/"
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
        RETENTION_DAYS=$(( DELAY_DAYS * 3 ))
        CUTOFF_COMMIT=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list -n 1 --before="$DELAY_DAYS days ago" HEAD 2>/dev/null || true)

        if [ -n "$CUTOFF_COMMIT" ]; then
          COMMIT_COUNT=$(git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" rev-list --count "$CUTOFF_COMMIT..HEAD")
          if [ "$COMMIT_COUNT" -gt 5 ]; then
            echo "Pruning historical commits older than $RETENTION_DAYS days (preserving baseline fallback)..."
            git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" reflog expire --expire=now --all || true
            git -c safe.directory="$TARGET_STATE_DIR" -C "$TARGET_STATE_DIR" gc --prune=now --aggressive || true
          fi
        fi