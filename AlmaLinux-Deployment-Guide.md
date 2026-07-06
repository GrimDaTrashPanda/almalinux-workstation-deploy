# AlmaLinux 10 Workstation Deployment Guide

This guide walks through what `deploy.sh` does, why each step exists, and what to check if something doesn't go as expected. AlmaLinux is a downstream rebuild of Red Hat Enterprise Linux (RHEL) — enterprise-stable, predictable release cadence, long support windows. That stability is exactly why a few common desktop tools need extra setup: they're not always in the default repos, and getting a full modern browser stack running takes a bit more than `dnf install`.

## Overview

AlmaLinux Workstation ships a clean, minimal GNOME desktop out of the box. It does not include a development toolchain, most everyday browsers, or a handful of common command-line utilities. This deployment brings a fresh install up to a genuinely usable daily-driver baseline in one pass, and does it in a way that's safe to run again later without duplicating anything.

## Prerequisites

- AlmaLinux 10 Workstation installed, GNOME desktop selected
- A normal (non-root) user account with `sudo` access
- Network connectivity

## Phase 1: CPU Microcode

Microcode updates patch CPU-level bugs and security issues (like Spectre/Meltdown-class vulnerabilities) that the OS alone can't fix — they need to be loaded at boot, before the kernel takes over scheduling.

The script detects your CPU vendor from `/proc/cpuinfo` and handles each case differently:

- **Intel:** installs `microcode_ctl` explicitly, since it's not always present by default
- **AMD:** no separate package needed — AMD microcode ships as part of `linux-firmware`, which is installed by default on AlmaLinux

If vendor detection fails for some reason, the script logs a warning and continues rather than stopping the whole deployment over one non-critical step.

## Phase 2: EPEL and CodeReady Builder

RHEL-based distributions split their package ecosystem into tiers, and two of those tiers matter here:

- **EPEL** (Extra Packages for Enterprise Linux) — a Fedora-maintained repo of packages that meet Red Hat's quality bar but aren't included in the base OS. Several tools this script installs (`fastfetch`, `duf`, `tldr`, `glances`) live here.
- **CRB** (CodeReady Builder) — a repo of build-time dependencies and libraries that many EPEL packages need in order to install cleanly. It's disabled by default and has to be explicitly enabled.

The script installs `epel-release` and enables CRB with `dnf config-manager --set-enabled crb`. The `|| true` at the end means the script won't stop if CRB is already enabled or the command errors for a reason that doesn't actually block the rest of the deployment.

## Phase 3: Native Toolkit

This installs the bulk of the daily-driver toolkit in one `dnf install` call:

| Package | Purpose |
|---|---|
| Development Tools (group) | Compiler toolchain and core build utilities |
| `git` | Version control |
| `firefox` | Default browser, present in AppStream |
| `glances` | Terminal system monitor |
| `fastfetch` | System info fetch tool (from EPEL) |
| `duf` | Disk usage utility (from EPEL) |
| `tldr` | Simplified command help pages (from EPEL) |
| `flatpak` | Sandboxed app runtime |

Because this is a single `dnf install -y` call for everything, `dnf` itself handles skipping anything already installed — no extra checks needed in the script.

## Phase 4: Firefox Wayland Rendering

By default, Firefox on many distributions still renders through XWayland (an X11 compatibility layer) rather than talking to Wayland directly, even on a Wayland session. Setting the `MOZ_ENABLE_WAYLAND` environment variable tells Firefox to use native Wayland rendering instead, which generally means smoother scrolling, correct fractional scaling, and lower input latency.

The script appends `MOZ_ENABLE_WAYLAND=1` to `/etc/environment` — a system-wide environment file read at login — and checks first so re-running the script doesn't add a duplicate line. This takes effect at your **next login**, not immediately.

## Phase 5: Flathub Remote

Flatpak is installed in Phase 3, but without a remote configured it has nothing to install from. This phase adds the Flathub remote, the largest cross-distro Flatpak repository, so Flatpak is immediately usable for anything not covered by the native toolkit above.

## Phase 6: Browser Stack (Chrome, Brave, Edge)

Chrome, Brave, and Edge aren't in AlmaLinux's default repos, so each needs its own official RPM repository added before `dnf` can see it:

| Browser | Repo source |
|---|---|
| Google Chrome | `dl.google.com/linux/chrome/rpm/stable/x86_64` |
| Brave | Brave's own S3-hosted `.repo` file, plus a signing key import |
| Microsoft Edge | Microsoft's official `yumrepos/edge`, plus a signing key import |

Each repo add is wrapped in a check for the resulting `.repo` file under `/etc/yum.repos.d/`, so re-running the script won't try to re-add a repo that's already configured. Once all three repos are in place, a single `dnf install` grabs all three browsers together.

> ⚠️ **Chromium-based browsers still need a manual one-time Wayland flag.** Unlike Firefox, Chrome/Brave/Edge don't pick up `MOZ_ENABLE_WAYLAND` — each needs `ozone-platform-hint` set to Wayland individually, in its own `://flags` page. See "After Running" below.

## Phase 7: Unified Update Utility

Some distributions split system updates into two categories — "official" packages versus everything else — because their package manager can cleanly tell the two apart. AlmaLinux doesn't need that distinction: everything installed here is either a `dnf`-tracked package (including Chrome, Brave, and Edge, once their repos are added) or a Flatpak. There's no third, harder-to-track tier.

So this deployment creates a **single** `update-workstation.sh` script that runs `sudo dnf upgrade -y` followed by `flatpak update -y`, and a matching GNOME `.desktop` launcher so it shows up in the app grid under "Update Workstation" — no terminal typing required for routine maintenance.

The script detects which terminal emulator is available (`gnome-terminal`, falling back to `kgx`, falling back to a plain `bash -c` invocation) so the launcher works correctly regardless of which terminal app is actually installed.

## After Running

1. **Log out and back in** — applies the Firefox Wayland environment variable.
2. **Set the Wayland flag in each Chromium browser individually:**
   - Chrome: `chrome://flags/#ozone-platform-hint`
   - Brave: `brave://flags/#ozone-platform-hint`
   - Edge: `edge://flags/#ozone-platform-hint`

   Set each to **Wayland**, click **Relaunch**. One-time step per browser.
3. **Confirm the launcher exists** — press **Super**, search "Update Workstation," confirm it appears in results.

## Safe to Re-Run

Every repo-add step checks for the resulting file first, `dnf install` naturally skips already-installed packages, and the update script/launcher are simply overwritten with identical content on a second run. Re-running `deploy.sh` after a partial failure, or just to confirm everything's still in place, won't cause duplicate entries or broken repos.

## Troubleshooting

**A.1 — "Could not determine CPU vendor" warning**
Rare, but harmless if it happens — it just means the microcode package wasn't installed. You can check your CPU vendor manually with `grep vendor_id /proc/cpuinfo` and install `microcode_ctl` yourself if you're on Intel.

**A.2 — `crb` enable command fails or warns**
Usually means it's already enabled, or the repo name differs slightly by AlmaLinux point release. Confirm with `dnf repolist all | grep crb` — if it shows up and is enabled, no action needed.

**A.3 — A browser won't launch after install**
Confirm the repo actually installed correctly: `rpm -q google-chrome-stable`, `rpm -q brave-browser`, or `rpm -q microsoft-edge-stable`. If any come back "package not installed," re-run the relevant section of `deploy.sh` — the repo-file check means it's safe to just run the whole script again.

**A.4 — Firefox still isn't using Wayland after logging back in**
Confirm the variable actually saved: `cat /etc/environment | grep MOZ_ENABLE_WAYLAND`. If it's missing, add it manually: `echo "MOZ_ENABLE_WAYLAND=1" | sudo tee -a /etc/environment`, then log out and back in again.

**A.5 — Update launcher doesn't appear in the app grid**
Run `update-desktop-database ~/.local/share/applications/` manually, then check again. Some GNOME Shell sessions need a re-login to refresh the app grid cache after a new `.desktop` file is added.
