# Changelog

What changed in each release of the installer, newest first. Every release is named after the day
it was published (`vYYYY.MM.DD`) and can be downloaded from the GitHub releases page.

## Unreleased

## v2026.10.25

<!-- auto: rewritten on every publish -->
- Built for Hyprland 0.56.2-4.1, Qt 6.12.0 and Python 3.14.
- Updated: Dock & widgets settings.

## v2026.10.24

<!-- auto: rewritten on every publish -->
- Built for Hyprland 0.56.2-4.1, Qt 6.12.0 and Python 3.14.
- Updated: Dock & widgets settings; Shell UI (Dock, Spotlight, widgets).

## v2026.10.22

<!-- auto: rewritten on every publish -->
- Built for Hyprland 0.56.2-4.1, Qt 6.12.0 and Python 3.14.
- Updated: Dock & widgets settings; Hyprland config; Shell UI (Dock, Spotlight, widgets); Top bar (Caelestia).

## v2026.10.20

<!-- auto: rewritten on every publish -->
- Built for Hyprland 0.56.2-4.1, Qt 6.12.0 and Python 3.14.
- Updated: Dock & widgets settings.

## v2026.10.19

- First public release: one file that installs the whole macOS-style desktop (Hyprland, the Caelestia
  top bar, the dock, launcher, Spotlight, widgets and title bars with traffic lights) on a fresh
  CachyOS + KDE Plasma system in 5-10 minutes. Plasma stays as it was and remains available at the login screen.
- One-command install: paste a single `curl … && bash …` line into a terminal (see the README).
- The README now has screenshots of the desktop.
- Releases publish automatically: the installer is rebuilt and uploaded whenever the desktop or its
  packages change, so the download link always gives you the current version.
- The project is now called **macOSxCaelestia**, and so is the installer: download and run
  `macOSxCaelestia.run` (the one-command install in the README uses the new name).
- The installer keeps its notes and backups in `~/.local/state/macOSxCaelestia*` folders, matching the new name.
- Each release now comes with this changelog; its notes on GitHub show what changed.
- Fixed: on plain Arch (not CachyOS) the installer stopped silently while installing packages, so none
  of the desktop's settings were copied and Hyprland started with its default look. The cause was the
  PipeWire volume control (pwvucontrol), which only CachyOS's own repository carries; it is now bundled
  with the installer like the other AUR apps, and the build refuses any package missing from Arch's repos.
- If installing packages fails, the installer now stops with a clear message that your settings were
  not installed yet, so you can fix the problem pacman shows and simply run it again.
- If the title-bar plugin has to be rebuilt for your Hyprland and its build tools can't be installed,
  the installer now carries on without title bars instead of stopping before your settings are copied.
- Already installed on plain Arch and got Hyprland's default look? Download the new file with the same
  one-command install and run it again; it picks up where the old one stopped.
- The README has a new Troubleshooting section, notes that no AUR helper (yay, paru) is needed, and
  lists the CPU the bundled apps need (x86-64-v3: Intel Haswell / AMD Zen 1 or newer).

<!-- auto: rewritten on every publish -->
- Built for Hyprland 0.56.2-4.1, Qt 6.12.0 and Python 3.14.
- Package updates: pwvucontrol 0.5.3-2 (new).
- Updated: Dock & widgets settings; Installed apps; Shell UI (Dock, Spotlight, widgets).
