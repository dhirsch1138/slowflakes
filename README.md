# Slowflakes

**10/24/2026** This is vibe slop I am playing with to implement a self directed version of determinatesystem's 'nixpkgs-weekly' channel that covers ALL inputs instead of just nixpkgs. I am adding this to github to dogfood it. I make no promises or guarantees. Read it yourself if you are feeling brave and want to try it. 

**Slowflakes** is a NixOS module that creates an isolated, time-delayed update buffer for your `flake.lock`. By maintaining a rolling background history in `/var/lib/slowflakes-state/`, it allows you to promote tested, multi-day-old lockfiles into your main NixOS configuration (`/etc/nixos`), shielding your system from sudden upstream regressions.

---

## 🚀 Quickstart

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

## 🛠️ CLI Tooling

Slowflakes provides three main command-line utilities:

* **`slowflakes-status`**: View background timer health, active vs target lock comparison, disk usage, and state history.
* **`slowflakes-update [DAYS]`**: Safely promote a qualifying N-day-old lock snapshot into `/etc/nixos`. Pass `0` for immediate promotion testing.
* **`slowflakes-cleanup`**: View state repo size or prune historical commits older than your retention policy.

Manual pages are available via `man slowflakes-status`, `man slowflakes-update`, and `man slowflakes-cleanup`.

---

## 🛡️ Safety Mechanisms

* **Uncommitted Changes Guard**: `slowflakes-update` detects uncommitted local edits to `flake.lock` and aborts to prevent overwriting local emergency hotfixes.
* **Hybrid mtime Check**: Evaluates both filesystem modification times and Git commit history.
* **Privilege Isolation**: The daily background service runs securely under the dedicated `slowflakes-bot` system user.
