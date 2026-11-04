# macOSxCaelestia

A macOS-style Linux desktop in one file: a top bar with floating pills, a permanent dock,
Spotlight search, desktop widgets, a Mission-Control-style Overview, window title bars with
traffic lights (the red, yellow and green buttons), frosted glass and Apple-style icons.

It's built on [Hyprland](https://hypr.land), the [Caelestia](https://github.com/caelestia-dots/shell) shell
and [Quickshell](https://quickshell.org). New to these words? See [Words you might not know](#words-you-might-not-know).

## Which Linux do I need?

The installer uses **pacman**, the package manager of Arch Linux and the distros built on it, and it bundles
packages built for Arch. So it runs on:

| Your system | Does it work? |
|---|---|
| **CachyOS** | Yes. This is what it's built and tested on. |
| **Arch Linux** | Yes. |
| **Other Arch-based distros** (EndeavourOS, Garuda, ArcoLinux…) | Should work: they use the same packages. Not tested. |
| **Manjaro** | Not recommended: Manjaro holds packages back for a few weeks, so they may be older than the ones the installer expects. |
| **Fedora, Ubuntu, Linux Mint, Pop!_OS, Debian, openSUSE…** | Not directly. See below. |

**On Fedora, Ubuntu, Mint or another non-Arch distro?** The installer won't change your system. It
offers to download CachyOS (a free, beginner-friendly Arch-based distro) and write it to a USB stick for you.
From that stick you can:

- try CachyOS without installing anything (it runs from the stick),
- install it next to your current system (you choose which one to start each time you turn the PC on), or
- replace your current system.

Back up your files before installing any operating system. Pick **KDE Plasma** as the desktop when
CachyOS asks, then run the install command below again.

**Your current desktop stays.** Whatever desktop you already use (Plasma, GNOME, Xfce…) keeps working.
This only adds a new choice, "Hyprland", to the login screen, and you can switch back any time.
KDE Plasma is the tested setup; with another desktop it should still work, because the installer only needs
a login screen to add itself to.

**Hardware:** a 64-bit Intel or AMD PC from about 2015 or newer (see [Known limits](#known-limits)).
Intel, AMD and NVIDIA graphics can all run Hyprland, but it's tested on Intel graphics.

## Install

**Before you start**

- Update and restart first: open a terminal and run `sudo pacman -Syu`, then restart.
  (`sudo` asks for your password because installing software changes the system.)
- Use a terminal inside your normal desktop, as your normal user (not `root`, not over SSH), and have your password ready.
- Be connected to the internet.
- Open Firefox once and close it, so the theme can find your Firefox profile (the folder where Firefox keeps your settings).

**Then run**

```sh
curl -LO https://github.com/exploitgamers/macOSxCaelestia/releases/latest/download/macOSxCaelestia.run && bash macOSxCaelestia.run
```

This downloads one file (`curl`) and runs it (`bash`). It asks before changing anything.
Answer yes, wait 5-10 minutes, then **log out and pick Hyprland** on the login screen
(usually from a small menu in a corner of the login screen). Your old desktop is still in that same menu.

## Screenshots

![Desktop](screenshots/desktop.png)
![Spotlight](screenshots/spotlight.png)
![Overview](screenshots/overview.png)
![Launcher](screenshots/launcher.png)
![Desktop Settings](screenshots/settings.png)
![Window with title bar](screenshots/window.png)

## Options

Add these after `bash macOSxCaelestia.run`:

| Option | What it does |
|---|---|
| `--yes` | don't ask, answer yes to everything |
| `--dry-run` | print every step, change nothing (a safe preview) |
| `--uninstall` | remove the installed config files and put your old ones back (packages stay) |

Example: `bash macOSxCaelestia.run --dry-run`.

## What it changes

- **Packages (apps and libraries):** `sudo pacman -Syu --needed …` installs Hyprland, the foot terminal, the
  fish shell, Firefox, the Thunar file manager, fonts, sound tools and more. This also updates the rest of
  your system. Then `sudo pacman -U …` installs the [AUR](#words-you-might-not-know) packages bundled inside
  the file (Caelestia shell and CLI, HyprMod, qtengine, Darkly, WhiteSur icons and cursors, pwvucontrol…).
  They come ready-built, so nothing is compiled and no AUR helper (yay, paru) is needed.
- **Your home folder:** settings files ("config files") in `~/.config/{hypr,caelestia,quickshell,foot,fish,fuzzel,gtk-3.0,gtk-4.0,nwg-look,Thunar,qtengine,btop}`,
  Thunar's `thunar.xml`, `~/.gtkrc-2.0`, `~/.config/starship.toml`, the `rice-*` helper commands in `~/.local/bin`,
  Quickshell in `~/.local/opt/quickshell-local`, the title-bar plugin in `~/.local/lib/hyprland/plugins`,
  a wallpaper in `~/Pictures/Wallpapers` and a `userChrome.css` (a Firefox style file) in Firefox's default-release profile.
  `~` means your home folder, for example `/home/alex`.
- **Backups:** every file it replaces is first copied to `~/.local/state/macOSxCaelestia-backup-<date>/`. Running it
  again keeps your own edits in `macOSxCaelestia-replaced-<date>/`. `--uninstall` puts them back.
- **Shared with your other desktop:** the GTK theme (how GNOME-style apps look: `gtk-3.0`, `gtk-4.0`, `~/.gtkrc-2.0`,
  `org.gnome.desktop.interface` settings), Thunar's preferences and the fish, foot, starship and btop settings.
  System Settings, the Thunar/AppImage/GTK settings apps and Background Services (uuctl) leave the app menus
  (Plasma's too); they open from Desktop Settings > More. Outside your home folder, only the installed packages and
  (if it's missing) the "Hyprland" entry on the login screen are added.

## After logging in

- **Super** is the Windows key (⌘ Command on a Mac keyboard).
- Super+Space: Spotlight search · Super+I: Desktop Settings · Super on its own: app launcher.
- `rice-doctor` (type it in a terminal): health check of the desktop (Quickshell/Qt match, title-bar plugin, shells running).
- **Widgets:** right-click a desktop widget and choose Edit to change it: clock style and city, first day of the
  week, weather location and units, which batteries or system meters to show, Notes text size, timer presets and
  the Photos folder.
- Weather uses your rough location from your internet address. To use a city instead, set it in the weather widget's Edit options.
- **Keep the laptop running with the lid closed:** click the battery in the top bar and turn on "Caffeinated"
  (the coffee cup). Closing the lid then only turns the screen off; the laptop doesn't sleep or lock. That also means
  anyone who opens the lid gets your desktop without a password, so turn it off when you leave the laptop somewhere.
  It turns itself off when you log out or restart.

## Troubleshooting

**Hyprland starts with its default look** (plain wallpaper, a yellow "autogenerated config" warning, no dock):
the installer didn't finish, so the settings never reached `~/.config`. Run the install command again and
read the last lines it prints. If pacman fails (a package conflict, an out-of-date mirror, meaning a download
server that hasn't caught up yet), the installer stops with a message saying your settings were not installed.
Fix what pacman reports, then run it again. Older downloads stopped here silently on plain Arch Linux.

**Nothing works and you want your old desktop back:** log out and pick your old desktop on the login screen.
To remove this desktop's settings, run `bash macOSxCaelestia.run --uninstall`.

## Updating

Run the install command again: the newest `macOSxCaelestia.run` carries the current packages and settings, and your
edits to installed files are kept aside (see Backups). What changed in each release is in [CHANGELOG.md](CHANGELOG.md).

This repository is history only (`git log -p payload/` shows every change). It leaves out the built file and the
bundled packages, so cloning it alone can't install anything: use the command above.

## Known limits

These are the version checks the installer does for you. You normally don't need to do anything.

- **Qt drift:** Qt is the toolkit the top bar and dock are drawn with. Quickshell is built for Qt 6.12. If your system
  has a newer Qt, the installer warns and switches to your distro's `quickshell` if that one matches; otherwise
  Quickshell must be rebuilt from source.
- **Hyprland drift:** the title-bar plugin only loads into the exact Hyprland version it was built for. If yours differs,
  the installer rebuilds it (about a minute). If that fails, windows have no title bars and everything else works.
- **Python drift:** caelestia-cli and HyprMod are packed for Python 3.14.
- Bundled AUR packages carry the versions from the build date; you can update them from the AUR later if you like.
- **CPU:** the bundled packages and Quickshell are built for x86-64-v3, a set of newer instructions that Intel Haswell
  and AMD Zen 1 or newer processors have (roughly 2015 on). On older processors the top bar and dock won't start.
  ARM computers (Raspberry Pi, Apple Silicon Macs) aren't supported.

## Words you might not know

| Word | What it means |
|---|---|
| **Distro** | A version of Linux, such as Fedora, Ubuntu or Arch. They share the same core but package software differently. |
| **Arch-based** | A distro built on Arch Linux (CachyOS, EndeavourOS, Garuda…). They share Arch's packages and its package manager, pacman. |
| **pacman** | The app store of Arch-based distros, used from the terminal. `sudo pacman -Syu` updates everything. |
| **AUR** | The Arch User Repository: community-made packages that aren't in Arch's official list. This installer bundles the ones it needs. |
| **Terminal** | The text window where you type commands. It's usually in the app menu as "Terminal" or "Konsole". |
| **Desktop environment** | The whole desktop: panels, menus, settings and apps. KDE Plasma and GNOME are desktop environments. |
| **Hyprland** | A window manager: the program that draws windows, moves them around and animates them. It replaces the one your desktop uses, only while you're logged into the Hyprland session. |
| **Wayland** | The modern way Linux apps show windows on screen. Hyprland is a Wayland window manager. Older apps that only know X11, the system before Wayland, still run through **Xwayland**. |
| **Caelestia** | The shell that draws the top bar, notifications and side panels. Here it's restyled to look like macOS. |
| **Quickshell** | The toolkit Caelestia and this project's dock, widgets and Spotlight are written with. |
| **Shell** | Here: the bars, docks and panels around your windows (not the command-line shell). |
| **Session** | One way of using the computer after logging in. Your login screen lists the sessions, e.g. "Plasma" and "Hyprland". |
| **Plugin** | An add-on loaded into Hyprland. The title-bar plugin (hyprbars) draws the traffic-light buttons. |
| **Rice / ricing** | Linux slang for customising how a desktop looks. The helper commands here start with `rice-`. |
| **Config files** | Plain text files that store settings, mostly in `~/.config`. |
