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