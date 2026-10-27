{ pkgs, config, ... }:

let
  cfg = config.services.slowflakes;

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

    # Declare runtime commands used by your automation script (e.g., git, ping)
    runtimeInputs = with pkgs; [
      git
      iputils   # for ping (if network check is used)
      coreutils
      gnugrep
    ];
  };

  # Helper function to convert booleans to string for bash consumption
  boolToString = b: if b then "true" else "false";

in {
  # Expose the built script derivation so systemd services can call it cleanly
  inherit automationScript;
}