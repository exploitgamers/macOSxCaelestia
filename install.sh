#!/usr/bin/env bash
# macOSxCaelestia installer (build @@BUILD_VERSION@@): a macOS-style Hyprland desktop
# (Hyprland Lua config, Caelestia shell, Quickshell dock/launcher/widgets, hyprbars title bars).
#
#   ./macOSxCaelestia.run              install (asks once)
#   ./macOSxCaelestia.run --yes        install without asking
#   ./macOSxCaelestia.run --dry-run    print every action, change nothing
#   ./macOSxCaelestia.run --uninstall  remove the installed configs and restore the backup (keeps packages)
#
# Not on Arch/CachyOS: offers to download the CachyOS ISO (and write it to a USB stick).
# Test hook: MACOSXCAELESTIA_STUB_PKGS=1 prints the sudo/pacman steps instead of running them.
set -euo pipefail

YES=0 DRY=0 MODE=install
STUB=${MACOSXCAELESTIA_STUB_PKGS:-0}
for a in "$@"; do
    case $a in
        -y | --yes) YES=1 ;;
        -n | --dry-run) DRY=1 ;;
        --uninstall) MODE=uninstall ;;
        -h | --help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# every path below is "$HOME/..."; an empty or / HOME would aim rm/rsync at the root
[ -n "${HOME:-}" ] && [ "$HOME" != / ] && [ -d "$HOME" ] || die "HOME is not set to your home folder"
STATE="$HOME/.local/state/macOSxCaelestia"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.local/state/macOSxCaelestia-backup-$STAMP"
# files earlier runs installed that are about to change (your edits); never restored automatically
REPLACED="$HOME/.local/state/macOSxCaelestia-replaced-$STAMP"
show() { printf '    %s\n' "$(printf '%q ' "$@")"; }
run()  { if [ $DRY = 1 ]; then printf '[dry-run]'; show "$@"; else "$@"; fi; }
sudo_run() {
    if [ $DRY = 1 ] || [ "$STUB" = 1 ]; then printf '[%s] sudo' "$([ $DRY = 1 ] && echo dry-run || echo stub)"; show "$@"
    else sudo "$@"; fi
}
ask() { # ask "question" -> 0 for yes
    [ $YES = 1 ] && return 0
    [ $DRY = 1 ] && { echo "[dry-run] would ask: $1"; return 0; }
    local r; read -r -p "$1 [y/N] " r </dev/tty; [[ $r == [yY]* ]]
}
major_minor() { echo "$1" | cut -d. -f1,2; }

# ======================================================================= not Arch: CachyOS ISO
offer_iso() {
    say "This installer needs CachyOS (or Arch Linux): no pacman found."
    command -v curl >/dev/null || die "curl is needed to download CachyOS. Get it from https://cachyos.org/download/"
    local base=https://mirror.cachyos.org/ISO/desktop latest iso dir
    latest=$(curl -fsSL --max-time 30 "$base/" | grep -oE 'href="[0-9]{6}/"' | grep -oE '[0-9]{6}' | sort -n | tail -1) ||
        die "could not reach $base"
    [ -n "$latest" ] || die "no ISO listed at $base"
    iso="cachyos-desktop-linux-$latest.iso"
    dir="$HOME/Downloads"
    if ask "Download the latest CachyOS desktop ISO ($iso, about 3 GB) to $dir?"; then
        run mkdir -p "$dir"
        run curl -fL -C - -o "$dir/$iso" "$base/$latest/$iso"
        run curl -fsSL -o "$dir/$iso.sha256" "$base/$latest/$iso.sha256"
        if [ $DRY = 0 ]; then
            say "Checking the sha256 against the official checksum file"
            local want got
            want=$(awk '{print $1; exit}' "$dir/$iso.sha256")
            got=$(sha256sum "$dir/$iso" | awk '{print $1}')
            [ -n "$want" ] && [ "$want" = "$got" ] || die "checksum mismatch ($got, expected $want) - delete $dir/$iso and retry"
            say "Checksum OK: $got"
        fi
        if command -v lsblk >/dev/null && ask "Write it to a USB stick now? (erases the stick)"; then
            write_usb "$dir/$iso"
        fi
    fi
    echo
    echo "Install CachyOS with KDE Plasma, then run this file again."
    exit 0
}

write_usb() { # never offers the disk that holds /
    local iso=$1 root_disk dev line model size mounts
    # btrfs prints /dev/x[/@]; -r: no tree glyphs; -s walks up through LUKS/LVM to the disk
    root_disk=$(lsblk -rsno NAME,TYPE "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null | awk '$2=="disk"{print $1}' | tail -1)
    [ -n "$root_disk" ] || { warn "Can't tell which disk holds the running system - not writing any USB stick. Use a tool like Fedora Media Writer or balenaEtcher."; return 0; }
    echo "Disks (the system disk ${root_disk:-?} is not offered):"
    lsblk -dno NAME,SIZE,MODEL,TRAN,TYPE | awk -v r="$root_disk" '$NF=="disk" && $1!=r && $1 !~ /^(zram|loop)/ {print "    /dev/" $0}'
    if [ $DRY = 1 ]; then
        echo "[dry-run] would ask for the device, show its model and size, require typing its name, then:"
        show sudo dd if="$iso" of=/dev/DEVICE bs=4M status=progress oflag=direct conv=fsync
        return 0
    fi
    read -r -p "Device to erase (e.g. /dev/sdb), empty to skip: " dev </dev/tty
    [ -n "$dev" ] || return 0
    dev=${dev#/dev/}
    # plain kernel names only: "../dev/nvme0n1" would slip past the root-disk comparison
    case $dev in '' | *[!a-z0-9]*) die "'$dev' is not a disk name like sdb" ;; esac
    [ -b "/dev/$dev" ] && [ "$(lsblk -dno TYPE "/dev/$dev")" = disk ] || die "/dev/$dev is not a whole disk"
    case $dev in zram* | loop*) die "/dev/$dev is not a USB stick" ;; esac
    [ "$dev" != "$root_disk" ] || die "refusing: /dev/$dev holds the running system"
    [ "$(lsblk -dno TRAN "/dev/$dev" | tr -d ' ')" = usb ] || [ "$(lsblk -dno RM "/dev/$dev" | tr -d ' ')" = 1 ] ||
        die "refusing: /dev/$dev is not a USB or removable disk"
    # MOUNTPOINT (not MOUNTPOINTS: missing in older util-linux); fail closed if lsblk can't tell
    mounts=$(lsblk -nro MOUNTPOINT "/dev/$dev") || die "can't read the mount points of /dev/$dev"
    [ -z "${mounts//[[:space:]]/}" ] || die "/dev/$dev has mounted partitions - unmount them first"
    model=$(lsblk -dno MODEL "/dev/$dev"); size=$(lsblk -dno SIZE "/dev/$dev")
    # destructive: always typed, even with --yes
    read -r -p "ERASE /dev/$dev ($model, $size)? Type the device name '$dev' to confirm: " line </dev/tty
    [ "$line" = "$dev" ] || { echo "Not confirmed - nothing written."; return 0; }
    sudo_run dd if="$iso" of="/dev/$dev" bs=4M status=progress oflag=direct conv=fsync
    sudo_run sync
    say "USB stick ready: boot from it."
}

# ======================================================================= uninstall
uninstall() {
    [ -f "$STATE/manifest" ] || die "nothing to uninstall ($STATE/manifest not found)"
    # moved aside, not deleted: they may carry edits made after installing
    local gone="$HOME/.local/state/macOSxCaelestia-removed-$STAMP"
    say "Moving $(wc -l < "$STATE/manifest") installed files to $gone"
    while IFS= read -r rel; do
        { [ -e "$HOME/$rel" ] || [ -L "$HOME/$rel" ]; } || continue
        run mkdir -p "$gone/$(dirname "$rel")" && run mv -f "$HOME/$rel" "$gone/$rel"
    done < "$STATE/manifest"
    # empty folders left behind
    awk -F/ '{p=$1; for (i=2; i<NF; i++) {print p; p=p "/" $i} if (NF>1) print p}' "$STATE/manifest" | sort -ru |
        while IFS= read -r d; do
            [ -d "$HOME/$d" ] && [ ! -L "$HOME/$d" ] && run rmdir --ignore-fail-on-non-empty "$HOME/$d" 2>/dev/null || true
        done
    # restore newest backup first, so the oldest (pre-install) copy of each file wins
    local bks i
    bks=("$HOME"/.local/state/macOSxCaelestia-backup-*)   # names sort by date
    for ((i = ${#bks[@]} - 1; i >= 0; i--)); do
        [ -d "${bks[i]}" ] || continue
        say "Restoring ${bks[i]}"
        run rsync -a --no-perms "${bks[i]}/" "$HOME/"   # cp -a dir/. would chmod $HOME to 755 too
    done
    # renamed once restored, so a later install + uninstall can't put these old copies back over newer edits
    for ((i = 0; i < ${#bks[@]}; i++)); do
        [ -d "${bks[i]}" ] && run mv "${bks[i]}" "$HOME/.local/state/macOSxCaelestia-restored-${bks[i]##*-backup-}"
    done
    if [ -f "$STATE/gsettings.before" ]; then
        if [ $DRY = 0 ] && test_bus; then
            echo "[stub] would restore the GTK gsettings from $STATE/gsettings.before"
        elif [ $DRY = 1 ] || have_bus; then
            say "Restoring GTK settings (gsettings)"
            local k v
            while IFS=$'\t' read -r k v; do run gsettings set org.gnome.desktop.interface "$k" "$v" || true; done < "$STATE/gsettings.before"
            run rm -f "$STATE/gsettings.before"
        else
            warn "No D-Bus session: GTK gsettings not restored (old values in $STATE/gsettings.before)"
        fi
    fi
    run rm -f "$STATE/manifest"
    say "Done. Packages were kept (remove them with pacman if you like). Old copies: ~/.local/state/macOSxCaelestia-{restored,removed,replaced}-*."
}

# ======================================================================= install
extract_payload() {
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/macOSxCaelestia.XXXXXX")
    trap 'rm -rf "$WORK"' EXIT
    local line
    line=$(awk '/^__MACOSXCAELESTIA_PAYLOAD__$/{print NR + 1; exit}' "$0")
    [ -n "$line" ] || die "payload marker missing - is this the .run file?"
    command -v zstd >/dev/null || die "zstd missing: sudo pacman -S zstd"
    tail -n +"$line" "$0" | tar -C "$WORK" --zstd -xf - || die "payload is damaged - download the .run again"
    # shellcheck source=/dev/null
    . "$WORK/meta.env"
}

preflight() {
    [ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (it asks for sudo itself)"
    command -v pacman >/dev/null || offer_iso
    curl -fsS --max-time 15 -o /dev/null https://archlinux.org 2>/dev/null ||
        curl -fsS --max-time 15 -o /dev/null https://cachyos.org 2>/dev/null ||
        { [ "$STUB" = 1 ] || [ $DRY = 1 ]; } || die "no internet connection"
    if [ $DRY = 0 ] && [ "$STUB" != 1 ]; then
        sudo -v || die "sudo does not work for ${USER:-$(id -un)}"
    fi
}

plan() {
    local nrepo naur
    nrepo=$(wc -l < "$WORK/repo-packages.txt"); naur=$(find "$WORK/pkgs" -name '*.pkg.tar.zst' | wc -l)
    cat <<EOF

macOSxCaelestia (built $BUILD_DATE for Hyprland $HYPR_VERSION, Qt $QT_BUILT, Caelestia $CAELESTIA)
Plan:
  1. sudo pacman -Syu --needed  ($nrepo repo packages; also updates the system)
  2. sudo pacman -U --needed    ($naur bundled AUR packages: Caelestia, HyprMod, qtengine, WhiteSur…)
  3. Quickshell built for Qt $QT_BUILT  -> ~/.local/opt/quickshell-local  (+ qs/quickshell wrappers)
  4. hyprbars title bars -> ~/.local/lib/hyprland/plugins  (rebuilt here if your Hyprland differs)
  5. configs into ~/.config (hypr, caelestia, quickshell, foot, fish, fuzzel, gtk, Thunar, qtengine…),
     rice-* helpers into ~/.local/bin, wallpaper into ~/Pictures/Wallpapers, GTK gsettings
     Existing files are backed up to $BACKUP
  6. Firefox: macOS-style userChrome.css in the default-release profile
KDE Plasma keeps its own settings; Hyprland is added to the login screen. Shared with Plasma: the GTK theme
(~/.config/gtk-3.0, gtk-4.0, ~/.gtkrc-2.0, gsettings), Thunar's preferences and the fish/foot/starship/btop
configs. System Settings, Thunar/AppImage/GTK settings and Background Services leave the app menus (also
Plasma's); they open from Desktop Settings > More.
EOF
}

install_packages() {
    say "Repo packages"
    # shellcheck disable=SC2046
    sudo_run pacman -Syu --needed --noconfirm $(cat "$WORK/repo-packages.txt") ||
        die "installing the repo packages failed (see pacman's error above). Your configs were NOT installed - fix that and run this again."
    say "Bundled AUR packages"
    sudo_run pacman -U --needed --noconfirm "$WORK"/pkgs/*.pkg.tar.zst ||
        die "installing the bundled packages failed (see pacman's error above). Your configs were NOT installed - fix that and run this again."
}

check_versions() {
    local py
    py=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo none)
    [ "$py" = "$PYTHON" ] || warn "Python is $py but the bundled caelestia-cli/HyprMod were built for $PYTHON: colour schemes or HyprMod may fail until you rebuild them from the AUR."
}

choose_quickshell() {
    local sys_qt repo_qt
    sys_qt=$(pacman -Q qt6-base 2>/dev/null | awk '{print $2}' | cut -d- -f1)
    if [ "$(major_minor "$sys_qt")" = "$(major_minor "$QT_BUILT")" ]; then
        say "Quickshell: bundled build matches Qt $sys_qt"
        return
    fi
    warn "Your Qt is ${sys_qt:-unknown}, the bundled Quickshell was built for $QT_BUILT."
    repo_qt=$( [ -x /usr/bin/quickshell ] && tr '\0' '\n' < /usr/bin/quickshell | grep -m1 -xE '6\.[0-9]+\.[0-9]+' || true)
    if [ -n "$repo_qt" ] && [ "$(major_minor "$repo_qt")" = "$(major_minor "$sys_qt")" ]; then
        say "Using the repo quickshell (built for Qt $repo_qt) instead"
        rm -rf "$WORK/home/.local/opt/quickshell-local" "$WORK/home/.local/bin/qs" "$WORK/home/.local/bin/quickshell"
    else
        warn "The repo quickshell doesn't match either (${repo_qt:-not installed}). Installing the bundled one; if the dock or bar crashes, build Quickshell from source for Qt $sys_qt."
    fi
}

hyprland_commit() { { XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-$WORK} Hyprland --version 2>/dev/null || true; } | sed -n 's/.* at commit \([0-9a-f]\{40\}\).*/\1/p' | head -1 || true; }

choose_hyprbars() {
    local now t0 plug="$WORK/home/.local/lib/hyprland/plugins"
    now=$(hyprland_commit)
    # no commit readable (Hyprland --version needs XDG_RUNTIME_DIR): same package version counts as a match
    [ -n "$now" ] || [ "$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')" != "$HYPR_VERSION" ] || now=$HYPR_COMMIT
    if [ "$now" = "$HYPR_COMMIT" ]; then say "Title bars: bundled plugin matches Hyprland ${now:0:8}"; return; fi
    warn "Hyprland here is $([ -n "$now" ] && echo "${now:0:8}" || echo unknown) (bundled plugin: ${HYPR_COMMIT:0:8}): rebuilding the title-bar plugin."
    if ! sudo_run pacman -S --needed --noconfirm cmake ninja pkgconf gcc; then
        warn "Could not install the build tools (cmake ninja pkgconf gcc): windows will have no macOS title bars (everything else works)."
        rm -f "$plug"/{libhyprbars.so,BUILT_FOR_HYPRLAND}
        return
    fi
    if [ $DRY = 1 ]; then echo "[dry-run] would build hyprbars in $WORK/hyprbars-src/hyprbars"; return; fi
    t0=$(date +%s)
    if (cd "$WORK/hyprbars-src/hyprbars" && cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null &&
        cmake --build build -j"$(nproc)" >/dev/null); then
        cp "$WORK/hyprbars-src/hyprbars/build/libhyprbars.so" "$plug/libhyprbars.so"
        # commit unknown: no stamp (rice-doctor then asks for a rebuild) instead of an empty or stale one
        if [ -n "$now" ]; then echo "$now" > "$plug/BUILT_FOR_HYPRLAND"; else rm -f "$plug/BUILT_FOR_HYPRLAND"; fi
        say "Title-bar plugin rebuilt in $(( $(date +%s) - t0 )) s"
    else
        warn "Title-bar plugin build failed: windows will have no macOS title bars (everything else works)."
        rm -f "$plug"/{libhyprbars.so,BUILT_FOR_HYPRLAND}
    fi
}

template() { # @@HOME@@ / @@USER@@ -> this user
    local h u f
    h=$(printf '%s' "$HOME" | sed 's/[&|\\]/\\&/g'); u=$(printf '%s' "${USER:-$(id -un)}" | sed 's/[&|\\]/\\&/g')
    while IFS= read -r f; do
        [ -f "$WORK/home/$f" ] && sed -i "s|@@HOME@@|$h|g; s|@@USER@@|$u|g" "$WORK/home/$f"
    done < "$WORK/templated.list"
    while IFS=$'\t' read -r f t; do
        [ -n "$f" ] && ln -sfn "${t//@@HOME@@/"$HOME"}" "$WORK/home/$f"
    done < "$WORK/symlinks.list"
}

install_files() {
    say "Installing configs (backup of replaced files: $BACKUP)"
    (cd "$WORK/home" && find . ! -type d | sed 's|^\./||') > "$WORK/files.list"
    if [ $DRY = 1 ]; then
        echo "[dry-run] would copy $(wc -l < "$WORK/files.list") files into $HOME; existing files that differ:"
        while IFS= read -r f; do
            if [ -e "$HOME/$f" ] || [ -L "$HOME/$f" ]; then
                cmp -s "$WORK/home/$f" "$HOME/$f" || echo "    back up + replace ~/$f"
            fi
        done < "$WORK/files.list"
        return
    fi
    mkdir -p "$STATE"
    # the user's own files go to BACKUP (restored by --uninstall); files a previous run installed
    # (in the manifest) and since edited go to REPLACED, so a re-run never silently drops edits
    local f to
    while IFS= read -r f; do
        { [ -e "$HOME/$f" ] || [ -L "$HOME/$f" ]; } || continue
        cmp -s "$WORK/home/$f" "$HOME/$f" && continue
        to=$BACKUP; grep -qxF -- "$f" "$STATE/manifest" 2>/dev/null && to=$REPLACED
        mkdir -p "$to/$(dirname "$f")" && cp -a "$HOME/$f" "$to/$f"
    done < "$WORK/files.list"
    # manifest first: a failed copy still leaves every touched file uninstallable
    cat "$WORK/files.list" "$STATE/manifest" 2>/dev/null | sort -u > "$STATE/manifest.new" || true
    mv "$STATE/manifest.new" "$STATE/manifest"
    # --no-perms: -a would also chmod existing folders, e.g. a 700 $HOME to the payload's 755
    rsync -a --no-perms "$WORK/home/" "$HOME/"
    [ -d "$BACKUP" ] && echo "  $(find "$BACKUP" ! -type d | wc -l) existing files backed up" || true
    [ -d "$REPLACED" ] && echo "  $(find "$REPLACED" ! -type d | wc -l) files changed since the last install saved to $REPLACED" || true
}

backup_one() { # $1 = absolute path under HOME, before we change it in place
    local rel=${1#"$HOME"/} to=$BACKUP
    [ -e "$1" ] || return 0
    grep -qxF -- "$rel" "$STATE/manifest" 2>/dev/null && to=$REPLACED   # ours from an earlier run
    mkdir -p "$to/$(dirname "$rel")"
    [ -e "$to/$rel" ] || cp -a "$1" "$to/$rel"
}

# gsettings write to the session's dconf through D-Bus; without a reachable bus `gsettings set` still exits 0
# (a stale DBUS_SESSION_BUS_ADDRESS too), so ping the bus instead of trusting the env
have_bus() { gdbus call --session --timeout 5 --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.GetId >/dev/null 2>&1; }
# stubbed test runs leave the real session's dconf alone unless given a private bus (dbus-run-session)
test_bus() {
    [ "$STUB" = 1 ] || return 1
    case ${DBUS_SESSION_BUS_ADDRESS:-} in '' | "unix:path=/run/user/$(id -u)/bus"* | "unix:path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"*) return 0 ;; esac
    return 1
}

gtk_settings() { # GTK4/libadwaita apps read the theme, icons, font and cursor from gsettings, not settings.ini
    say "GTK settings (gsettings org.gnome.desktop.interface)"
    local k v old
    if [ $DRY = 1 ] || test_bus; then
        while IFS=$'\t' read -r k v; do printf '[%s]' "$([ $DRY = 1 ] && echo dry-run || echo stub)"; show gsettings set org.gnome.desktop.interface "$k" "$v"; done < "$WORK/gsettings.list"
        return
    fi
    if ! have_bus || ! gsettings list-keys org.gnome.desktop.interface >/dev/null 2>&1; then
        warn "No D-Bus session (or no gsettings): GTK gsettings not set. Run this file again from a desktop session to apply them."
        return
    fi
    while IFS=$'\t' read -r k v; do
        old=$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null) || continue
        # the value from before the first install wins: --uninstall puts it back
        grep -q "^$k"$'\t' "$STATE/gsettings.before" 2>/dev/null || printf '%s\t%s\n' "$k" "$old" >> "$STATE/gsettings.before"
        gsettings set org.gnome.desktop.interface "$k" "$v" || warn "gsettings: could not set $k"
    done < "$WORK/gsettings.list"
}

firefox_profile() {
    command -v firefox >/dev/null || { [ $DRY = 1 ] || [ "$STUB" = 1 ]; } || { warn "Firefox not installed - skipping its theme"; return; }
    local root ini path rel
    find_profile() {
        for root in "$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox"; do
            ini="$root/profiles.ini"; [ -f "$ini" ] || continue
            path=$(awk -F= '/^\[/{n="";p="";r=1} /^Name=/{n=$2} /^Path=/{p=$2} /^IsRelative=/{r=$2}
                n=="default-release" && p!="" {print (r==1 ? R "/" : "") p; exit}' R="$root" "$ini")
            [ -n "$path" ] && [ -d "$path" ] && { echo "$path"; return 0; }
        done
        return 1
    }
    if ! path=$(find_profile); then
        say "Firefox: creating a default-release profile"
        if [ $DRY = 1 ]; then echo "[dry-run]    firefox --headless --createprofile default-release"; return; fi
        MOZ_NO_REMOTE=1 firefox --headless --createprofile default-release >/dev/null 2>&1 || true
        path=$(find_profile) || { warn "Firefox profile could not be created - skipping its theme"; return; }
    fi
    say "Firefox theme -> $path"
    [ $DRY = 1 ] && return
    rel=${path#"$HOME"/}
    backup_one "$path/chrome/userChrome.css"; backup_one "$path/user.js"
    mkdir -p "$path/chrome"
    cp "$WORK/firefox/userChrome.css" "$path/chrome/userChrome.css"
    touch "$path/user.js"
    local pref
    while IFS= read -r pref; do
        grep -qF "${pref%%,*}" "$path/user.js" || echo "$pref" >> "$path/user.js"
    done < "$WORK/firefox/user.js"
    printf '%s\n' "$rel/chrome/userChrome.css" "$rel/user.js" >> "$STATE/manifest"
}

session_entry() {
    if [ -f /usr/share/wayland-sessions/hyprland.desktop ]; then
        say "Login screen: Hyprland session entry present"
        return
    fi
    say "Adding a Hyprland entry to the login screen"
    local tmp="${WORK}/hyprland.desktop"
    printf '[Desktop Entry]\nName=Hyprland\nComment=An intelligent dynamic tiling Wayland compositor\nExec=Hyprland\nType=Application\n' > "$tmp"
    sudo_run install -Dm644 "$tmp" /usr/share/wayland-sessions/hyprland.desktop
}

overlay_check() {
    local now built
    now=$(pacman -Q caelestia-shell 2>/dev/null || true)
    built=$(cat "$HOME/.config/quickshell/caelestia/.built-from" 2>/dev/null || true)
    if [ -n "$now" ] && [ "$now" != "$built" ] && [ $DRY = 0 ]; then
        say "Rebuilding the Caelestia overlay for $now"
        "$HOME/.local/bin/rice-caelestia-overlay" || warn "Caelestia overlay failed: stock Caelestia will load"
    fi
}

finish() {
    [ $DRY = 1 ] && { echo; say "Dry run finished: nothing was changed."; return; }
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -x "$HOME/.local/bin/rice-doctor" ]; then
        "$HOME/.local/bin/rice-doctor" || true
    else
        echo "(After logging in to Hyprland, run 'rice-doctor' for a health check.)"
    fi
    echo
    say "Installed. Log out, pick Hyprland on the login screen."
    echo "    Undo: $0 --uninstall    (your old files: $BACKUP)"
}

main() {
    if [ "$MODE" = uninstall ]; then uninstall; exit 0; fi
    preflight
    extract_payload
    plan
    ask "Go ahead?" || { echo "Nothing changed."; exit 0; }
    install_packages
    check_versions
    choose_quickshell
    choose_hyprbars
    template
    install_files
    gtk_settings
    firefox_profile
    session_entry
    overlay_check
    finish
}

main
exit 0
