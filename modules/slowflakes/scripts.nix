{ pkgs, config, ... }:

let
  cfg = config.services.slowflakes;

  # Helper function to create an app from a static script file
  mkApp = name: pkgs.writeShellApplication {
    inherit name;

    # Inject module options as environment variables, followed by the script body
    text = ''
      export REPO_PATH="${cfg.repoPath}"
      export STATE_FOLDER_NAME="/var/lib/${cfg.stateFolderName}"
      export DELAY_DAYS="${toString cfg.delayDays}"
    '' + builtins.readFile ./resources/scripts/${name}.sh;

    # Declare runtime commands your scripts rely on
    runtimeInputs = with pkgs; [
      git
      coreutils
      gnugrep
      findutils
    ];
  };

  # Helper function to convert booleans to string for bash consumption
  boolToString = b: if b then "true" else "false";

in {
  slowflakes-status = mkApp "slowflakes-status";
  slowflakes-update = mkApp "slowflakes-update";
  slowflakes-cleanup = mkApp "slowflakes-cleanup";
}