{ pkgs, ... }:

let
  updateDoc = pkgs.writeText "slowflakes-update.1.scd" (
    builtins.readFile ./../resources/manPages/slowflakes-update.txt
  );

  statusDoc = pkgs.writeText "slowflakes-status.1.scd" (
    builtins.readFile ./../resources/manPages/slowflakes-status.txt
  );

  cleanupDoc = pkgs.writeText "slowflakes-cleanup.1.scd" (
    builtins.readFile ./../resources/manPages/slowflakes-cleanup.txt
  );
in {
  slowflakesManPagesPackage = slowflakesManPagesPackage;
  package = slowflakesManPagesPackage; # Backward-compatibility alias
}
