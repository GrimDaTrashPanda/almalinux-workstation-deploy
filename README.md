# AlmaLinux Workstation Baseline Deployment

A single, idempotent script that takes a fresh AlmaLinux 10 Workstation install (GNOME) to a fully provisioned baseline: EPEL, native toolkit, Flathub, a full browser stack, Wayland tuning, and a unified update workflow with a GNOME launcher.

Full background and rationale: [AlmaLinux-Deployment-Guide.md](./AlmaLinux-Deployment-Guide.md)

Built to make a Linux workstation deployment as close to one-command-easy as possible — clone, run, done.

## Prerequisites

- AlmaLinux 10 Workstation already installed (GNOME desktop environment)
- An internet connection for the initial `dnf` and repo setup

## Usage

```bash
git clone https://github.com/GrimDaTrashPanda/almalinux-workstation-deploy.git
cd almalinux-workstation-deploy
chmod +x deploy.sh
./deploy.sh
```

Run as your normal user, not root — it calls `sudo` internally where needed.

## What it does

1. Detects CPU vendor and installs Intel microcode if applicable (AMD microcode is bundled into `linux-firmware` by default)
2. Enables the EPEL repository and the CodeReady Builder (CRB) repo
3. Installs the native toolkit: Development Tools group, git, firefox, glances, fastfetch, duf, tldr, flatpak
4. Sets `MOZ_ENABLE_WAYLAND=1` for native Firefox Wayland rendering
5. Adds the Flathub remote
6. Adds official repos for Chrome, Brave, and Edge, then installs all three
7. Creates a single unified `update-workstation.sh` script and matching GNOME launcher

## After running

- Log out and back in (applies the Wayland env var)
- Set the Wayland flag manually in each Chromium browser — `chrome://flags/#ozone-platform-hint`, `brave://flags/#ozone-platform-hint`, `edge://flags/#ozone-platform-hint` — switch to **Wayland**, relaunch. One-time per browser.
- Press **Super**, search "Update" — confirm the launcher appears

## Safe to re-run

Every install step checks for an existing repo file before adding it, and `dnf` itself skips already-installed packages. Re-running won't duplicate repo entries or reinstall already-current software.

## Why one update script instead of a split workflow

AlmaLinux has no separate "foreign package" tier the way some other distros do — everything here is either an official `dnf`-tracked package or a Flatpak. A single `update-workstation.sh` covers both in one pass, so there's no split-update naming convention to explain here.
