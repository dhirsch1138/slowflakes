{ pkgs, ... }:

let
  updateDoc = pkgs.writeText "slowflakes-update.1.scd" ''
slowflakes-update(1)

# NAME
slowflakes-update - pull a time-shifted historical flake.lock snapshot

# SYNOPSIS
*slowflakes-update* [_delay_days_]

# DESCRIPTION
Queries the isolated slowflakes state repository for a historical lockfile commit from at least the configured delay threshold (or the specified _delay_days_ argument) ago. It extracts the snapshot using read-only *git show* and writes it to *./flake.lock* in the current working directory.

# OPTIONS
_delay_days_
	Optional integer specifying the number of days of history delay to target. Defaults to the configured *delayDays* option (typically 7).

# EXIT STATUS
*0*
	Success.
*1*
	Path validation failure (not executed within *repoPath*), missing state repository, stale snapshot warning error, or local hotfix protection abort.

# AUTHORS
Slowflakes Contributors.
'';

  statusDoc = pkgs.writeText "slowflakes-status.1.scd" ''
slowflakes-status(1)

# NAME
slowflakes-status - display diagnostic status of the slowflakes isolated state repository

# SYNOPSIS
*slowflakes-status*

# DESCRIPTION
Inspects the isolated rolling state repository located under */var/lib/slowflakes-state*, reporting total stored snapshots, oldest snapshot timestamp, latest commit metadata, and recent update history.

# EXIT STATUS
*0*
	Success.

# AUTHORS
Slowflakes Contributors.
'';

  cleanupDoc = pkgs.writeText "slowflakes-cleanup.1.scd" ''
slowflakes-cleanup(1)

# NAME
slowflakes-cleanup - purge the isolated slowflakes rolling state repository

# SYNOPSIS
*slowflakes-cleanup*

# DESCRIPTION
An interactive operator-confirmed utility to wipe and completely destroy the isolated rolling state repository and its update history (*sudo rm -rf /var/lib/slowflakes-state*). The background systemd service will automatically re-initialize it fresh on its next scheduled run.

# EXIT STATUS
*0*
	Success or user aborted.

# AUTHORS
Slowflakes Contributors.
'';

  slowflakesManPagesPackage = pkgs.runCommand "slowflakes-manpages" {
    nativeBuildInputs = [ pkgs.scdoc ];
  } ''
    mkdir -p $out/share/man/man1
    scdoc < ${updateDoc} > $out/share/man/man1/slowflakes-update.1
    scdoc < ${statusDoc} > $out/share/man/man1/slowflakes-status.1
    scdoc < ${cleanupDoc} > $out/share/man/man1/slowflakes-cleanup.1
    gzip $out/share/man/man1/*.1
  '';
in {
  slowflakesManPagesPackage = slowflakesManPagesPackage;
  package = slowflakesManPagesPackage; # Backward-compatibility alias
}
