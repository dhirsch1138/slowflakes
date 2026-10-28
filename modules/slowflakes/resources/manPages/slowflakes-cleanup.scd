slowflakes-cleanup(1)

# NAME
slowflakes-cleanup - purge the isolated slowflakes rolling state repository

# SYNOPSIS
*slowflakes-cleanup*

# DESCRIPTION
An interactive operator-confirmed utility to wipe and completely destroy the isolated rolling state repository and its update history (*rm -rf /var/lib/slowflakes-state*). The background systemd service will automatically re-initialize it fresh on its next scheduled run.

# EXIT STATUS
*0*
	Success or user aborted.

# AUTHORS
Slowflakes Contributors.