#!/usr/bin/env bash
set -euo pipefail

# environment variables declarations should be prepended in scripts.nix, as it will have the context of the options
#
#    # Inject module options as environment variables, followed by the script body
#    text = ''
#      export REPO_PATH="${cfg.repoPath}"
#      export STATE_FOLDER_NAME="${cfg.stateFolderName}"
#      export DELAY_DAYS="${toString cfg.delayDays}"
#    '' + builtins.readFile ./resources/scripts/${name}.sh;
TARGET_STATE_DIR = "/var/lib/${STATE_FOLDER_NAME}"

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