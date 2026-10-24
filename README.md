# Slowflakes

**Slowflakes** is a NixOS module that creates an isolated, time-delayed update buffer for your system's `flake.lock`. By maintaining a rolling background history in `/var/lib/slowflakes-state/`, it allows you to promote tested, multi-day-old lockfiles into your main NixOS configuration (`/etc/nixos`), shielding your system from sudden upstream regressions. 

This is vibe slop I am playing with to implement a self directed version of determinatesystem's 'nixpkgs-weekly' channel that covers ALL inputs instead of just nixpkgs. I am adding this to github to dogfood it. I make no promises or guarantees. Read it yourself if you are feeling brave and want to try it. 

---

## How it works

Slowflakes has two pieces:

### Systemd Service
A service that generates and stores a history of "flake.lock" files for so that Slowflakes can promote 'aged' versions.
* Runs daily
* Runs under a local unprivileged service account "slowflakes-bot"
* Stores state data in /var/lib/***`services.slowflakes.stateFolderName`*** (default: /var/lib/slowflakes-state)
* Maintains a git repository in the state folder to provide a historical store of "flake.lock" files for the system.
* Reads the system flake.nix in ***`services.slowflakes.repoPath`*** (default: /etc/nixos),
* Copies the system flake.nix to the state folder.
* Runs 'nix flake update' on the flake.nix in the state folder to create a current flake.lock
* Commits the lock file the git repo.
* Prunes the git repo to control space growth.

### CLI Tools
This project includes tools to allow the user to utilize the historical flakes maintained by the service.
* **`slowflakes-status`**: View background timer health, active vs target lock comparison, disk usage, and state history.
* **`slowflakes-update [optional - DAYS]`**: Safely promote a qualifying N-day-old lock snapshot into `/etc/nixos`. Pass `0` for immediate promotion testing.
  * This is intended to be a replacement for "nix flake update". It promotes the 'aged' flake.lock that the service built X days ago. 
* **`slowflakes-cleanup`**: Wipes all data from the service's state folder, allowing it to be reset by the service or just removing state.
  
Manual pages are available via `man slowflakes-status`, `man slowflakes-update`, and `man slowflakes-cleanup`.

---

## But what if an update can't wait X days?
This is a useful framework, but inflexible. There are a myriad of reasons why a user would need to get the latest packages **now**, like critical security patches. No worries:

`nix flake update` still works exactly as before.

* As the service stores own state data, it is not impacted.
* **`slowflakes-update`** will refuse to promote an older historical lock file over a new system flake.lock.
* The operator may choose to not promote lock files from the historical store until sufficient time that the desired time buffer is re-established. 

---

## Quickstart

### 1. Add as a Flake Input

In your NixOS system `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or nixos-26.05, etc.

    slowflakes = {
      url = "github:dhirsch1138/slowflakes";
      inputs.nixpkgs.follows = "nixpkgs"; # Bind to host system nixpkgs
    };
  };

  outputs = { self, nixpkgs, slowflakes, ... }: {
    nixosConfigurations.helios = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix

        # Import slowflakes module
        slowflakes.nixosModules.default
      ];
    };
  };
}
```

### 2. Enable in `configuration.nix`

```nix
{
  services.slowflakes = {
    enable = true;
    delayDays = 7;                # Quarantine threshold in days
    enableLocalAutomation = true; # Daily background state update timer
    repoPath = "/etc/nixos";       # Path to target repo
  };
}
```

Rebuild your system:

```bash
sudo nixos-rebuild switch
```

---

## Uninstall / cleanup instructions

The services and tools are implemented by nix, and will be removed when the module is disabled

### Optional - clean up state data
As all state data is confined to /var/lib/***`services.slowflakes.stateFolderName`*** (default: /var/lib/slowflakes-state), and can be cleaned up with **`slowflakes-cleanup`**. Note: that tool is part of the module, so it should be ran *before* the module is disabled.

## Safety Mechanisms

* **Uncommitted Changes Guard**: `slowflakes-update` detects uncommitted local edits to `flake.lock` and aborts to prevent overwriting local emergency hotfixes.
* **State data confined to /var/lib/.../ path**
  * The historical flake.lock files are stored in a isolated folder
  * Interaction with the rest of the system is limited to promotion of flake.lock files from the historical store into the production path, and is managed by  **`slowflakes-update`** 
