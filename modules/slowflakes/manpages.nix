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

  slowflakesManPagesPackage =
    pkgs.runCommand "slowflakes-manpages"
      {
        nativeBuildInputs = [ pkgs.scdoc ];
      }
      ''
        mkdir -p $out/share/man/man1
        scdoc < ${updateDoc} > $out/share/man/man1/slowflakes-update.1
        scdoc < ${statusDoc} > $out/share/man/man1/slowflakes-status.1
        scdoc < ${cleanupDoc} > $out/share/man/man1/slowflakes-cleanup.1
        gzip $out/share/man/man1/*.1
      '';
in
{
  slowflakesManPagesPackage = slowflakesManPagesPackage;
  package = slowflakesManPagesPackage; # Backward-compatibility alias
}
