# Slowflakes

**Slowflakes** is a NixOS module that creates an isolated, time-delayed update buffer for your system's `flake.lock`. By maintaining a rolling background history in `/var/lib/slowflakes-state/`, it allows you to promote community tested, multi-day-old lockfiles into your main NixOS configuration (`/etc/nixos`), shielding your system from sudden upstream regressions. 

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

## Configuration Options

Configure `slowflakes` in your NixOS configuration under the `services.slowflakes` namespace.

### Summary Table

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `services.slowflakes.enable` | `boolean` | `false` | Enables the `slowflakes` module and installs CLI scripts. |
| `services.slowflakes.delayDays` | `integer` | `7` | Mandatory quarantine buffer age (in days) required before promoting lockfiles. |
| `services.slowflakes.repoPath` | `string` | `"/etc/nixos"` | Target directory where the production `flake.lock` file resides. |
| `services.slowflakes.stateFolderName` | `string` | `"slowflakes-state"` | Directory name created inside `/var/lib/` to house the isolated state repository. |
| `services.slowflakes.enableLocalAutomation` | `boolean` | `true` | Enables the background `systemd` timer for daily automated state updates. |
| `services.slowflakes.networkCheckEnabled` | `boolean` | `true` | Enables pre-flight network reachability checks before running background updates. |
| `services.slowflakes.gitUserName` | `string` | `"Slowflakes Bot"` | Git author name recorded for automated state commits. |
| `services.slowflakes.gitUserEmail` | `string` | `"slowflakes-bot@localhost"` | Git author email recorded for automated state commits. |

### Detailed Technical Definitions

#### `services.slowflakes.enable`
* **Type**: `boolean`
* **Default**: `false`
* **Description**: Controls whether the `slowflakes` module is enabled. When set to `true`, it registers the `slowflakes-bot` system user/group, installs the `slowflakes-update`, `slowflakes-status`, and `slowflakes-cleanup` CLI utilities, and generates the accompanying `scdoc` man pages into the system profile.

#### `services.slowflakes.delayDays`
* **Type**: `integer`
* **Default**: `7`
* **Description**: Defines the quarantine threshold in days. When running `slowflakes-update`, the script queries the isolated state repository and retrieves the newest snapshot that is **at least `delayDays` old**, shielding your system from zero-day upstream package regressions. This value is also used to calculate the rolling historical git log retention policy (`delayDays * 3`).

#### `services.slowflakes.repoPath`
* **Type**: `string (absolute path)`
* **Default**: `"/etc/nixos"`
* **Description**: Specifies the root path of your primary NixOS Git repository containing `flake.nix` and `flake.lock`. `slowflakes-update` will modify `flake.lock` in this directory, and `slowflakes-status` will check this directory for uncommitted local edits or hotfixes before applying promotions.

#### `services.slowflakes.stateFolderName`
* **Type**: `string`
* **Default**: `"slowflakes-state"`
* **Description**: Sets the directory name for the isolated Git repository stored under `/var/lib/` (e.g., `/var/lib/slowflakes-state`). This repository runs in isolation under the unprivileged `slowflakes-bot` system user, preventing permission conflicts with your root-owned `/etc/nixos` repo.

#### `services.slowflakes.enableLocalAutomation`
* **Type**: `boolean`
* **Default**: `true`
* **Description**: Enables a daily background `systemd` timer (`slowflakes-localrepo-update.timer`) and oneshot service (`slowflakes-localrepo-update.service`). Every 24 hours, the service executes `nix flake update` inside `/var/lib/slowflakes-state` and commits a daily snapshot if changes are detected.

#### `services.slowflakes.networkCheckEnabled`
* **Type**: `boolean`
* **Default**: `true`
* **Description**: Performs an ICMP ping check (`8.8.8.8` / `1.1.1.1`) prior to running the background `nix flake update` routine. If the machine is offline or behind a captive portal, the service exits gracefully with status `0` without marking the `systemd` unit as failed.

#### `services.slowflakes.gitUserName`
* **Type**: `string`
* **Default**: `"Slowflakes Bot"`
* **Description**: Configures the Git author name assigned to automated daily commits created inside `/var/lib/slowflakes-state`.

#### `services.slowflakes.gitUserEmail`
* **Type**: `string`
* **Default**: `"slowflakes-bot@localhost"`
* **Description**: Configures the Git email address assigned to automated daily commits created inside `/var/lib/slowflakes-state`.

---

## Uninstall / cleanup instructions

The services and tools are implemented by nix, and will be removed when the module is disabled

### Optional - clean up state data
As all state data is confined to /var/lib/***`services.slowflakes.stateFolderName`*** (default: /var/lib/slowflakes-state), and can be cleaned up with **`slowflakes-cleanup`**. Note: that tool is part of the module, so it should be ran *before* the module is disabled.

---

## Safety Mechanisms

* **Uncommitted Changes Guard**: `slowflakes-update` detects uncommitted local edits to `flake.lock` and aborts to prevent overwriting local emergency hotfixes.
* **State data confined to /var/lib/.../ path**
  * The historical flake.lock files are stored in a isolated folder
  * Interaction with the rest of the system is limited to promotion of flake.lock files from the historical store into the production path, and is managed by  **`slowflakes-update`** 
