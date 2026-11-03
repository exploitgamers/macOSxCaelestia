#!/usr/bin/env bash
# Build dist/macOSxCaelestia.run: a self-extracting installer of this desktop
# (Hyprland Lua config + Caelestia + the `qs -c macos` shell + hyprbars title bars).
# Only READS the live setup; everything is staged under ./payload and packed into the .run.
# Usage: ./build.sh            (needs: rsync bsdtar zstd jq pacman perl strip gsettings)
set -euo pipefail

SRC_HOME=${HOME:?}           # the machine the payload is copied from
SRC_USER=$(id -un)
HERE=$(cd "$(dirname "$0")" && pwd)
P="$HERE/payload"
H="$P/home"
DIST="$HERE/dist"

# same-length rewrite of $SRC_HOME/ inside a binary keeps it valid
unhome() { H0="$SRC_HOME/" perl -0777 -pi -e 'BEGIN { $h = $ENV{H0}; $r = "/build/" . ("x" x (length($h) - 8)) . "/" } s{\Q$h\E}{$r}g' "$1"; }
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mbuild failed:\033[0m %s\n' "$*" >&2; exit 1; }
for c in rsync bsdtar zstd jq pacman perl strip gsettings; do command -v "$c" >/dev/null || die "missing $c"; done

rm -rf "$P"
mkdir -p "$H" "$P/pkgs" "$P/firefox" "$P/hyprbars-src" "$DIST"

# ---------------------------------------------------------------- config files
say "Copying configs"
copy() { # copy <path relative to SRC_HOME> [rsync excludes…]
    local rel=$1; shift
    [ -e "$SRC_HOME/$rel" ] || die "missing $SRC_HOME/$rel"
    mkdir -p "$H/$(dirname "$rel")"
    if [ -d "$SRC_HOME/$rel" ]; then
        rsync -a "$@" "$SRC_HOME/$rel/" "$H/$rel/"
    else
        rsync -a "$SRC_HOME/$rel" "$H/$rel"
    fi
}
JUNK=(--exclude='*.bak' --exclude='*.before-*' --exclude='*.before*' --exclude='*.tmp' --exclude='*.orig' --exclude='*.rej' --exclude='*~')

copy .config/caelestia "${JUNK[@]}"
copy .config/quickshell/macos "${JUNK[@]}" --exclude=.claude --exclude=CLAUDE.md --exclude=AGENTS.md \
    --exclude=AI_WORKFLOW.md --exclude=SESSION_HANDOFF.md --exclude=.omni-tools --exclude=scripts \
    --exclude=.gitignore --exclude=.qmlls.ini --exclude=.git
copy .config/quickshell/caelestia "${JUNK[@]}"   # Caelestia overlay: symlinks into /etc/xdg + patched files
copy .config/hypr "${JUNK[@]}"
copy .config/foot/foot.ini
copy .config/fish/config.fish
copy .config/fish/functions/fish_greeting.fish
copy .config/fuzzel/fuzzel.ini
copy .config/qtengine
copy .config/gtk-3.0
copy .config/gtk-4.0
copy .gtkrc-2.0
copy .config/nwg-look
copy .config/Thunar "${JUNK[@]}"
copy .config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
copy .config/starship.toml
copy .config/btop/btop.conf
for b in qs quickshell rice-caelestia-overlay rice-doctor rice-ensure-shells rice-icon-tiles rice-nothp rice-session-env \
    rice-restart rice-term-colors rice-thunar-usb rice-usb-notify; do
    copy ".local/bin/$b"
done
copy .local/share/icons/WhiteSur-dark                # icon symlinks into /usr/share/icons
copy .local/share/applications/desktop-settings.desktop
# keep it out of Plasma's menus
grep -q '^OnlyShowIn=' "$H/.local/share/applications/desktop-settings.desktop" ||
    echo 'OnlyShowIn=Hyprland;' >> "$H/.local/share/applications/desktop-settings.desktop"
# Desktop Settings > More opens these with gtk-launch; NoDisplay=true copies keep them out of the launcher
for d in systemsettings io.github.bluemancz.hyprmod thunar-settings appimagelaunchersettings uuctl nwg-look; do
    copy ".local/share/applications/$d.desktop"
done
# GTK keys GTK4/libadwaita apps read from gsettings (applied by install.sh)
for k in gtk-theme icon-theme font-name cursor-theme cursor-size color-scheme; do
    printf '%s\t%s\n' "$k" "$(gsettings get org.gnome.desktop.interface "$k")"
done > "$P/gsettings.list"
! grep -q $'\t$' "$P/gsettings.list" || die "gsettings get returned nothing"

# colour scheme + wallpaper (state that is not private)
for f in scheme.json sequences.txt theme/term-legible.seq theme/waybar-colors.css wallpaper/path.txt; do
    copy ".local/state/caelestia/$f"
done
WALL=$(cat "$SRC_HOME/.local/state/caelestia/wallpaper/path.txt")
case "$WALL" in "$SRC_HOME"/*) ;; *) die "wallpaper outside HOME: $WALL" ;; esac
copy "${WALL#"$SRC_HOME"/}"

# ---------------------------------------------------------------- scrub / adapt
say "Scrubbing personal bits"
# Rootless-Podman DOCKER_HOST would break a real Docker on the target
perl -ni -e 'print unless /DOCKER_HOST|Docker-compatible API|Strix.s sandbox/' \
    "$H/.config/caelestia/hypr-user.lua" "$H/.config/caelestia/user-config.fish"
# Dock/launcher pins: drop apps the installer does not install
jq --argjson skip '["codium","equibop","DaVinciResolve","spotify","com.anthropic.Claude","org.vinegarhq.Sober","com.rtosta.zapzap","org.kde.kdenlive"]' '
    .dock.pinned |= map(select(. as $a | $skip | index($a) | not)) |
    .launcher.pinned |= map(select(. as $a | $skip | index($a) | not)) |
    .widgets.weatherLocation = "" | .sound.appVolumes = {}' \
    "$SRC_HOME/.config/caelestia/macos.json" > "$H/.config/caelestia/macos.json"
# Thunar: this machine's window size and column widths
perl -ni -e 'print unless /name="last-(window-[a-z-]+|separator-position|[a-z-]*column-widths)"/' \
    "$H/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml"

# ---------------------------------------------------------------- Quickshell build
say "Quickshell (local build for Qt $(cat "$SRC_HOME/.local/opt/quickshell-local/BUILT_WITH_QT"))"
copy .local/opt/quickshell-local
QSB="$H/.local/opt/quickshell-local/bin/quickshell"
strip --strip-all "$QSB"                    # 221 MB of debug info -> ~7 MB
# __FILE__ paths in log messages: same-length rewrite keeps the binary valid
unhome "$QSB"
QT_BUILT=$(tr '\0' '\n' < "$QSB" | grep -m1 -xE '6\.[0-9]+\.[0-9]+' || true)  # SIGPIPE from tr is fine
[ -n "$QT_BUILT" ] || die "no Qt version string in quickshell"

# ---------------------------------------------------------------- hyprbars
say "hyprbars"
HB="$SRC_HOME/.local/opt/hyprbars-build"
copy .local/lib/hyprland/plugins/libhyprbars.so
copy .local/lib/hyprland/plugins/BUILT_FOR_HYPRLAND
strip --strip-unneeded "$H/.local/lib/hyprland/plugins/libhyprbars.so"
unhome "$H/.local/lib/hyprland/plugins/libhyprbars.so"
rsync -a --exclude=build "$HB/src/hyprbars/" "$P/hyprbars-src/hyprbars/"   # patched tree
cp "$HB/macos-lights.patch" "$P/hyprbars-src/"
cp "$HB/src/LICENSE" "$P/hyprbars-src/" 2>/dev/null || true

# ---------------------------------------------------------------- Firefox
cp "$SRC_HOME/.config/mozilla/firefox/"*.default-release/chrome/userChrome.css "$P/firefox/"
grep '^user_pref' "$SRC_HOME/.config/mozilla/firefox/"*.default-release/user.js > "$P/firefox/user.js"

# ---------------------------------------------------------------- symlinks that point into SRC_HOME
# rewritten by the installer (rsync would copy them verbatim)
: > "$P/symlinks.list"
while IFS= read -r -d '' l; do
    t=$(readlink "$l")
    case "$t" in "$SRC_HOME"/*)
        printf '%s\t%s\n' "${l#"$H"/}" "@@HOME@@${t#"$SRC_HOME"}" >> "$P/symlinks.list"; rm "$l" ;;
    esac
done < <(find "$H" -type l -print0)

# ---------------------------------------------------------------- templating
say "Templating $SRC_HOME -> @@HOME@@, $SRC_USER -> @@USER@@"
: > "$P/templated.list"
while IFS= read -r f; do
    perl -pi -e "s{\Q$SRC_HOME\E}{\@\@HOME\@\@}g; s{\Q$SRC_USER\E}{\@\@USER\@\@}g" "$f"
    echo "${f#"$H"/}" >> "$P/templated.list"
done < <(grep -rlI --exclude-dir=quickshell-local -e "$SRC_USER" "$H" || true)

# ---------------------------------------------------------------- AUR packages (repacked from this machine)
# shortcut: rebuilt from installed files like fakepkg does (no fakepkg installed); files edited
# since install are packed as they are now (pacman -Qkk showed only icon caches).
AUR=(caelestia-shell caelestia-cli qt6-m3shapes-git libcava python-materialyoucolor ttf-rubik-vf
     qtengine darkly-bin whitesur-icon-theme whitesur-cursor-theme-git caelestia-firefox-theme
     hyprmod python-hyprland-config python-hyprland-monitors python-hyprland-schema
     python-hyprland-socket python-hyprland-state appimagelauncher
     pwvucontrol)   # pwvucontrol: CachyOS repo + AUR only, not in Arch's repos
say "Repacking ${#AUR[@]} AUR packages"
repack() {
    local name=$1 ver db tmp
    ver=$(pacman -Q "$name" | awk '{print $2}')
    db=/var/lib/pacman/local/$name-$ver
    [ -f "$db/desc" ] || die "no pacman db entry for $name"
    tmp=$(mktemp -d "$P/.repack.XXXX")
    # .PKGINFO from the local db's desc
    awk -v drop="${2:-}" '
        /^%[A-Z0-9]+%$/ { key=$0; next }
        /^$/ { key=""; next }
        key=="%NAME%"      { print "pkgname = " $0; print "pkgbase = " $0 }
        key=="%VERSION%"   { print "pkgver = " $0 }
        key=="%DESC%"      { print "pkgdesc = " $0 }
        key=="%URL%"       { print "url = " $0 }
        key=="%ARCH%"      { print "arch = " $0 }
        key=="%BUILDDATE%" { print "builddate = " $0 }
        key=="%PACKAGER%"  { print "packager = " $0 }
        key=="%SIZE%"      { print "size = " $0 }
        key=="%LICENSE%"   { print "license = " $0 }
        key=="%DEPENDS%"   { if ($0 != drop) print "depend = " $0 }
        key=="%OPTDEPENDS%"{ print "optdepend = " $0 }
        key=="%PROVIDES%"  { print "provides = " $0 }
        key=="%CONFLICTS%" { print "conflict = " $0 }
        key=="%REPLACES%"  { print "replaces = " $0 }
    ' "$db/desc" > "$tmp/.PKGINFO"
    # backup= entries (config files pacman should keep)
    awk '/^%BACKUP%$/{f=1;next} /^$/{f=0} f{split($0,a,"\t"); print "backup = " a[1]}' "$db/files" >> "$tmp/.PKGINFO"
    [ -f "$db/install" ] && cp "$db/install" "$tmp/.INSTALL"
    pacman -Qlq "$name" | sed 's|^/||' | grep -v '/$' > "$tmp/.list"
    (cd / && bsdtar -cf - --no-recursion -T "$tmp/.list") | (cd "$tmp" && bsdtar -xpf -)
    rm "$tmp/.list"
    # shellcheck disable=SC2035,SC2046 # package members are usr/, etc/…, never dash-named; .INSTALL is optional
    (cd "$tmp" && LANG=C bsdtar -czf .MTREE --format=mtree --uid 0 --gid 0 --uname root --gname root \
        --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' .PKGINFO * \
        $( [ -f .INSTALL ] && echo .INSTALL ) &&
     LANG=C bsdtar --zstd -cf "$P/pkgs/$name-$ver-$(awk -F' = ' '/^arch/{print $2}' .PKGINFO).pkg.tar.zst" \
        --uid 0 --gid 0 --uname root --gname root .MTREE .PKGINFO $( [ -f .INSTALL ] && echo .INSTALL ) *)
    rm -rf "$tmp"
}
for a in "${AUR[@]}"; do
    case $a in
        caelestia-shell) repack "$a" quickshell-git ;;   # Quickshell is bundled (or repo `quickshell`)
        *) repack "$a" ;;
    esac
done

# ---------------------------------------------------------------- repo packages (checked now)
say "Checking repo package names"
grep -v '^\s*#' "$HERE/repo-packages.txt" | tr -s ' \t' '\n' | grep . > "$P/repo-packages.txt"
# only Arch's own default repos count: CachyOS-only packages ([cachyos*]) don't exist on plain Arch,
# and [multilib] is off in Arch's default pacman.conf
ARCH_PKGS=$(pacman -Slq core extra | sort -u) && [ -n "$ARCH_PKGS" ] ||
    die "pacman -Slq core extra listed nothing (are those repos in pacman.conf and synced?)"
missing=$(sort -u "$P/repo-packages.txt" | comm -23 - <(echo "$ARCH_PKGS") | tr '\n' ' ')
[ -z "$missing" ] || die "not in Arch's core/extra (CachyOS-only or AUR - move to AUR=(...)): $missing"
# AUR deps that must come from the repos (kept with their version constraint)
for f in "$P"/pkgs/*.pkg.tar.zst; do
    bsdtar -xOf "$f" .PKGINFO | sed -n 's/^depend = //p'
done | sort -u > "$P/.deps"
own=$(for a in "${AUR[@]}"; do echo "$a"; done)
while read -r d; do
    grep -qxF "${d%%[<>=]*}" <<<"$own" && continue
    # repo/<dep> resolves provides (sh, libfoo.so=1-64) and versions (foo>=1.2) inside that repo only; -dd: just the target
    pacman -Sddp "core/$d" >/dev/null 2>&1 || pacman -Sddp "extra/$d" >/dev/null 2>&1 ||
        die "AUR dependency $d is not provided by Arch's core/extra"
done < "$P/.deps"
rm "$P/.deps"
DL=$(xargs pacman -Sp --print-format '%s' < "$P/repo-packages.txt" 2>/dev/null | awk '{s+=$1} END{print s+0}')

# ---------------------------------------------------------------- metadata
HYPR_COMMIT=$(cat "$SRC_HOME/.local/lib/hyprland/plugins/BUILT_FOR_HYPRLAND")
cat > "$P/meta.env" <<EOF
BUILD_DATE=$(date +%F)
QT_BUILT=$QT_BUILT
HYPR_COMMIT=$HYPR_COMMIT
HYPR_VERSION=$(pacman -Q hyprland | awk '{print $2}')
CAELESTIA=$(pacman -Q caelestia-shell | awk '{print $2}')
PYTHON=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')
DOWNLOAD_ESTIMATE=$DL
EOF

# ---------------------------------------------------------------- privacy check (fails the build on a hit)
say "Privacy grep"
PAT="@gmail|$SRC_USER|api[_-]?key|apikey|secret|password|passwd|token|BEGIN [A-Z ]*PRIVATE KEY|ssh-(rsa|ed25519)"
(cd "$P" && grep -rniIE --exclude-dir=pkgs "$PAT" .) > "$DIST/privacy-grep.txt" || true
if grep -iE "$SRC_USER|@gmail|PRIVATE KEY|ssh-(rsa|ed25519)" "$DIST/privacy-grep.txt"; then die "personal data left in payload"; fi
echo "  $(wc -l < "$DIST/privacy-grep.txt") generic hits (code identifiers), listed in dist/privacy-grep.txt"

# ---------------------------------------------------------------- pack
say "Packing"
tar -C "$P" --zstd -cf "$DIST/payload.tar.zst" --exclude='.repack.*' --owner=0 --group=0 --numeric-owner .   # no user name in tar headers
{
    sed "s/@@BUILD_VERSION@@/$(date +%Y%m%d)/" "$HERE/install.sh"
    echo "__MACOSXCAELESTIA_PAYLOAD__"
    cat "$DIST/payload.tar.zst"
} > "$DIST/macOSxCaelestia.run"
rm "$DIST/payload.tar.zst"
chmod +x "$DIST/macOSxCaelestia.run"
say "Done: $DIST/macOSxCaelestia.run ($(du -h "$DIST/macOSxCaelestia.run" | cut -f1)); repo download ≈ $((DL / 1048576)) MiB"
