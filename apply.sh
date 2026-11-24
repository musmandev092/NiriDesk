#!/bin/bash
# NiriDesk setup. Usage: apply.sh [system] [home]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
done_() { printf '    \033[32mok\033[0m  %s\n' "$*"; }
note() { printf '    \033[33m!!\033[0m  %s\n' "$*"; }
in_container() { [ -f /run/.toolboxenv ] || [ -f /run/.containerenv ]; }

in_container && { echo "Run apply.sh on the host, not inside a toolbox." >&2; exit 1; }
SUDO=sudo
TOOLBOX=${NIRIDESK_TOOLBOX:-0}; [ -e "$HERE/.toolbox" ] && TOOLBOX=1; [ "$TOOLBOX" = 1 ] || TOOLBOX=0
FW=() FW_CHANGED=0
if [ "$(id -u)" -eq 0 ]; then
    [ "$*" = system ] || { echo "Run apply.sh as your user (as root only: apply.sh system)." >&2; exit 1; }
    SUDO=""
fi
if [ -n "$(find "$HERE" -perm /022 ! -type l -print -quit 2>/dev/null)" ]; then
    chmod -R go-w "$HERE" 2>/dev/null || true
fi

BACKUP=/var/backups/niridesk
sys_put() {
    local src=$1 dst=$2 mode=${3:-0644}
    if $SUDO cmp -s "$src" "$dst" 2>/dev/null; then done_ "$dst"; return 1; fi
    # keep the first original
    if [ -e "$dst" ] && ! $SUDO test -e "$BACKUP$dst"; then
        $SUDO install -d -m 0700 "$BACKUP" && $SUDO cp -a --parents "$dst" "$BACKUP/"
    fi
    $SUDO install -D -m "$mode" "$src" "$dst"
    done_ "$dst (updated)"
    return 0
}

fetch() { curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 --connect-timeout 15 "$@"; }

fw_set() {
    local op=$1 kind=$2 val=$3 has=0
    $SUDO "${FW[@]}" "--query-$kind=$val" >/dev/null 2>&1 && has=1
    if [ "$op" = add ] && [ "$has" = 0 ]; then
        $SUDO "${FW[@]}" "--add-$kind=$val" >/dev/null && FW_CHANGED=1
    elif [ "$op" = remove ] && [ "$has" = 1 ]; then
        $SUDO "${FW[@]}" "--remove-$kind=$val" >/dev/null && FW_CHANGED=1
    fi
    return 0
}

has_nvidia() {
    local d
    case ${NIRIDESK_NVIDIA:-auto} in 1) return 0 ;; 0) return 1 ;; esac
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
        case $(cat "$d/class" 2>/dev/null) in 0x0300*|0x0302*) return 0 ;; esac
    done
    return 1
}

install_missing() {
    local label=$1 p missing=(); shift
    for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if [ ${#missing[@]} -eq 0 ]; then done_ "$label"; return 0; fi
    if $SUDO dnf -y -q --setopt=install_weak_deps=False install "${missing[@]}"; then
        done_ "$label (installed: ${missing[*]})"
    else note "$label: could not install ${missing[*]}; retried on next run"; fi
}

PKGS_DESKTOP=(niri xwayland-satellite dms greetd xdg-desktop-portal-gnome xdg-desktop-portal-gtk
    gnome-keyring gnome-keyring-pam polkit power-profiles-daemon upower dbus-tools
    policycoreutils-python-utils xdg-user-dirs xdg-terminal-exec wl-clipboard grim slurp swappy
    brightnessctl adw-gtk3-theme dconf fastfetch)
PKGS_APPS=(brave-origin foot imv mpv mpv-mpris Thunar thunar-volman thunar-archive-plugin tumbler xarchiver
    featherpad galculator gnome-disk-utility btop nano gvfs gvfs-fuse gvfs-mtp gvfs-smb)
PKGS_MEDIA=(ffmpeg-libs pipewire pipewire-alsa pipewire-pulseaudio wireplumber pulseaudio-utils alsa-utils)
PKGS_SYSTEM=(cups cups-pk-helper avahi nss-mdns plymouth plymouth-system-theme firewalld grub2-tools-extra)
PKGS_FONTS=(google-noto-sans-vf-fonts google-noto-serif-vf-fonts google-noto-sans-mono-vf-fonts
    google-noto-nastaliq-urdu-fonts google-noto-sans-arabic-vf-fonts google-noto-naskh-arabic-vf-fonts
    google-noto-sans-cjk-fonts google-noto-serif-cjk-fonts google-noto-sans-thai-vf-fonts
    google-noto-sans-bengali-vf-fonts google-noto-sans-devanagari-vf-fonts google-noto-sans-gurmukhi-vf-fonts
    google-noto-color-emoji-fonts dejavu-sans-fonts dejavu-sans-mono-fonts dejavu-serif-fonts
    adwaita-sans-fonts adwaita-mono-fonts)

BLACKLIST_ARGS="rd.driver.blacklist=nouveau,nova_core modprobe.blacklist=nouveau,nova_core"
NOUVEAU_ARGS="$BLACKLIST_ARGS nvidia-drm.fbdev=1"

# an Intel/AMD display GPU next to the NVIDIA one (laptops, desktops with iGPU)
has_other_gpu() {
    local d
    for d in /sys/bus/pci/devices/*; do
        case $(cat "$d/class" 2>/dev/null) in 0x0300*|0x0380*) ;; *) continue ;; esac
        case $(cat "$d/vendor" 2>/dev/null) in 0x8086|0x1002) return 0 ;; esac
    done
    return 1
}

do_system() {
    say "system (sudo)"
    [ -z "$SUDO" ] || $SUDO -n true 2>/dev/null || $SUDO -v

    install_missing "desktop (niri, DMS, portals, keyring, power profiles)" "${PKGS_DESKTOP[@]}"
    install_missing "apps (Brave, foot, Thunar, FeatherPad, galculator, imv, mpv, Disks, btop, nano)" "${PKGS_APPS[@]}"
    install_missing "sound and video codecs" "${PKGS_MEDIA[@]}"
    install_missing "printing, boot logo, firewall" "${PKGS_SYSTEM[@]}"
    install_missing "fonts" "${PKGS_FONTS[@]}"

    if rpm -q tuned-ppd >/dev/null 2>&1; then
        $SUDO dnf -y -q swap tuned-ppd power-profiles-daemon && done_ "power profiles: tuned-ppd -> power-profiles-daemon"
    fi
    systemctl is-enabled -q power-profiles-daemon 2>/dev/null || $SUDO systemctl enable --now power-profiles-daemon >/dev/null 2>&1 || true

    if [ "$TOOLBOX" = 1 ]; then
        install_missing "toolbox" toolbox
    else done_ "toolbox: not selected (touch .toolbox and rerun to add it)"; fi

    if [ -f /etc/greetd/config.toml ] && grep -q -- '--command sway' /etc/greetd/config.toml; then
        $SUDO sed -i 's/--command sway/--command niri/' /etc/greetd/config.toml && done_ "login screen: niri (updated)"
    else done_ "login screen: niri"; fi

    # text console on Ctrl+Alt+F2
    if ! systemctl is-enabled -q getty@.service 2>/dev/null; then
        $SUDO systemctl enable getty@.service >/dev/null 2>&1 && done_ "text console login (enabled)"
    else done_ "text console login"; fi

    if [ "$(plymouth-set-default-theme 2>/dev/null)" = bgrt ]; then done_ "boot screen: bgrt"
    elif $SUDO plymouth-set-default-theme bgrt && $SUDO dracut -f --regenerate-all >/dev/null 2>&1; then
        done_ "boot screen: bgrt (updated, initramfs rebuilt)"
    else note "boot screen: could not switch to bgrt"; fi

    sys_put "$HERE/etc/local-bin/sudoless" /usr/local/bin/sudoless 0755 || true

    # external monitor brightness (DDC)
    sys_put "$HERE/etc/udev/60-niridesk-ddc.rules" /etc/udev/rules.d/60-niridesk-ddc.rules \
        && $SUDO udevadm control --reload && $SUDO udevadm trigger --subsystem-match=i2c-dev || true
    sys_put "$HERE/etc/modules-load.d/i2c-dev.conf" /etc/modules-load.d/i2c-dev.conf \
        && $SUDO modprobe i2c-dev 2>/dev/null || true

    if has_nvidia; then
        sys_put "$HERE/etc/local-bin/niridesk-nvidia-sync" /usr/local/bin/niridesk-nvidia-sync 0755 || true
        sys_put "$HERE/etc/local-bin/prime-run" /usr/local/bin/prime-run 0755 || true
        sys_put "$HERE/etc/local-bin/niridesk-nvidia-memclock" /usr/local/bin/niridesk-nvidia-memclock 0755 || true
        sys_put "$HERE/etc/dracut.conf.d/90-niridesk-nvidia.conf" /etc/dracut.conf.d/90-niridesk-nvidia.conf || true
        sys_put "$HERE/etc/nvidia/50-limit-free-buffer-pool-in-wayland-compositors.json" \
            /etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json || true
        if sys_put "$HERE/etc/systemd/system/nvidia-memclock-lock.service" /etc/systemd/system/nvidia-memclock-lock.service; then
            $SUDO systemctl daemon-reload
        fi
        if bash "$HERE/etc/local-bin/niridesk-nvidia-sync"; then
            done_ "NVIDIA driver (kmod matches newest kernel)"
            $SUDO grubby --update-kernel=ALL --args="$NOUVEAU_ARGS" && done_ "nouveau blacklisted"
            for s in nvidia-hibernate nvidia-suspend nvidia-resume nvidia-suspend-then-hibernate nvidia-powerd nvidia-memclock-lock; do
                systemctl is-enabled -q "$s.service" 2>/dev/null || $SUDO systemctl enable "$s.service" >/dev/null 2>&1 || true
            done
            done_ "NVIDIA power services, memory clock lock, prime-run"
        elif has_other_gpu; then
            # no driver: nouveau can take the whole session down (black login screen),
            # so keep it off and let the Intel/AMD GPU drive the display
            $SUDO grubby --update-kernel=ALL --args="$BLACKLIST_ARGS" && done_ "nouveau blacklisted (Intel/AMD graphics in use)"
            note "NVIDIA: no driver for the newest kernel yet; screen runs on Intel/AMD graphics, outputs wired to the NVIDIA GPU stay dark. Run niridesk-nvidia-sync later."
        else
            # NVIDIA is the only GPU: nouveau is the only way to light the screen
            $SUDO grubby --update-kernel=ALL --remove-args="$NOUVEAU_ARGS" || true
            note "NVIDIA: no driver for the newest kernel yet and no other GPU; nouveau left enabled. Run niridesk-nvidia-sync later."
        fi
    else
        done_ "Hardware: Intel/AMD graphics (NVIDIA skipped)"
    fi

    local font=/boot/grub2/fonts/adwaita-mono-48.pf2
    if [ ! -f "$font" ]; then
        $SUDO mkdir -p /boot/grub2/fonts
        if $SUDO grub2-mkfont -s 48 -o "$font" /usr/share/fonts/adwaita-mono-fonts/AdwaitaMono-Regular.ttf 2>/dev/null; then
            done_ "GRUB font: adwaita-mono-48.pf2 (generated)"
        else note "GRUB font: grub2-mkfont failed"; fi
    else done_ "GRUB font: adwaita-mono-48.pf2"; fi
    if [ -f "$font" ] && [ -f /etc/default/grub ] && ! grep -qxF "GRUB_FONT=$font" /etc/default/grub; then
        $SUDO sed -i '/^GRUB_FONT=/d' /etc/default/grub
        echo "GRUB_FONT=$font" | $SUDO tee -a /etc/default/grub >/dev/null
        $SUDO grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 && done_ "GRUB_FONT (updated, grub.cfg regenerated)"
    fi

    sys_put "$HERE/etc/yum.repos.d/claude-desktop.repo" /etc/yum.repos.d/claude-desktop.repo || true

    local rel ls_ver ls_have tmp icon=/usr/local/share/icons/hicolor/512x512/apps/localsend.png
    rel=$(fetch https://api.github.com/repos/localsend/localsend/releases/latest) || rel=""
    ls_ver=$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' <<<"$rel" 2>/dev/null) || ls_ver=""
    [[ $ls_ver =~ ^[0-9]+(\.[0-9]+)*$ ]] || ls_ver=""
    ls_have=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' /opt/localsend/data/flutter_assets/version.json 2>/dev/null) || ls_have=""
    if [ -z "$ls_ver" ]; then note "LocalSend: GitHub not reachable; left as it is (${ls_have:-not installed})"
    elif [ "$ls_have" = "$ls_ver" ]; then done_ "LocalSend $ls_ver"
    else
        tmp=$(mktemp -d)
        if gh_release_asset localsend/localsend "LocalSend-$ls_ver-linux-x86-64\.tar\.gz" "$tmp/ls.tgz"; then
            $SUDO rm -rf /opt/localsend.new && $SUDO mkdir -p /opt/localsend.new
            $SUDO tar -xzf "$tmp/ls.tgz" -C /opt/localsend.new --no-same-owner
            $SUDO rm -rf /opt/localsend && $SUDO mv /opt/localsend.new /opt/localsend
            done_ "LocalSend $ls_ver (installed, SHA-256 checked)"
        else note "LocalSend: download or SHA-256 check failed; left as it is (${ls_have:-not installed})"; fi
        rm -rf "$tmp"
    fi
    if [ -x /opt/localsend/localsend_app ]; then
        $SUDO ln -sfn /opt/localsend/localsend_app /usr/local/bin/localsend
        cmp -s /opt/localsend/data/flutter_assets/assets/img/logo-512.png "$icon" \
            || $SUDO install -D -m 0644 /opt/localsend/data/flutter_assets/assets/img/logo-512.png "$icon" \
            || note "LocalSend: icon not found in this release"
        $SUDO rm -f /usr/local/share/applications/localsend.desktop
        sys_put "$HERE/etc/localsend/org.localsend.localsend_app.desktop" \
            /usr/local/share/applications/org.localsend.localsend_app.desktop || true
    fi

    if sys_put "$HERE/etc/systemd/resolved.conf.d/40-niridesk.conf" /etc/systemd/resolved.conf.d/40-niridesk.conf; then
        $SUDO systemctl try-restart systemd-resolved 2>/dev/null || true
    fi
    if sys_put "$HERE/etc/sysctl.d/40-niridesk.conf" /etc/sysctl.d/40-niridesk.conf; then
        $SUDO sysctl -q -p /etc/sysctl.d/40-niridesk.conf 2>/dev/null || true
    fi

    systemctl is-enabled -q firewalld 2>/dev/null || $SUDO systemctl enable --now firewalld >/dev/null 2>&1 || true
    FW=(firewall-cmd --permanent); FW_CHANGED=0
    $SUDO firewall-cmd --state >/dev/null 2>&1 || FW=(firewall-offline-cmd)
    fw_set remove service http
    fw_set remove service https
    fw_set remove service ssh
    fw_set add service mdns
    fw_set add port 53317/tcp
    fw_set add port 53317/udp
    if [ "$FW_CHANGED" = 1 ]; then
        [ "${FW[0]}" = firewall-cmd ] && $SUDO firewall-cmd --reload >/dev/null
        done_ "firewall rules (updated)"
    else done_ "firewall rules"; fi
    done_ "firewall: LocalSend 53317 and mDNS open, SSH closed"

    [ -f "$HERE/.extras" ] && bash "$HERE/extras.sh" system
    return 0
}

gh_release_asset() {
    local repo=$1 pat=$2 out=$3 rel name url sum
    rel=$(fetch "https://api.github.com/repos/$repo/releases/latest") || return 1
    read -r name url sum < <(python3 -I -c '
import json, re, sys
d = json.load(sys.stdin); pat = re.compile(sys.argv[1], re.I)
for a in d["assets"]:
    if pat.fullmatch(a["name"]) and (a.get("digest") or "").startswith("sha256:"):
        print(a["name"], a["browser_download_url"], a["digest"][7:]); break' "$pat" <<<"$rel") || return 1
    [ -n "${name:-}" ] || return 1
    fetch -o "$out" "$url" || return 1
    echo "$sum  $out" | sha256sum -c --status
}

link() {
    local src="$HERE/$1" dst="$HOME/$2"
    if [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then done_ "~/$2"; return; fi
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        local bak="$HOME/.local/state/niridesk/backup/$2.$(date +%s)"
        mkdir -p "$(dirname "$bak")" && mv "$dst" "$bak"
    fi
    ln -s "$src" "$dst"
    done_ "~/$2 -> NiriDesk (linked)"
}

# for files the apps rewrite
copy_once() {
    local src="$HERE/$1" dst="$HOME/$2"
    if [ -e "$dst" ]; then done_ "~/$2 (kept)"; return; fi
    install -D -m 0644 "$src" "$dst" && done_ "~/$2 (copied)"
}

ini_default() {
    python3 -I - "$@" <<'EOF'
import configparser, os, sys
path, section, key, value = sys.argv[1:]
c = configparser.ConfigParser(interpolation=None, strict=False); c.optionxform = str
c.read(path)
if c.has_option(section, key):
    sys.exit(0)
if not c.has_section(section):
    c.add_section(section)
c.set(section, key, value)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    c.write(f, space_around_delimiters=False)
EOF
}

HIDE_DESKTOP=(panel-preferences thunar-settings thunar-volman-settings thunar-bulk-rename xarchiver foot-server footclient nvidia-settings)

do_home() {
    say "home"
    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.local/share/color-schemes" "$HOME/.local/bin" \
        "$HOME/.local/share/applications"

    link home/.bashrc.d/niridesk.sh .bashrc.d/niridesk.sh
    link home/.config/fastfetch .config/fastfetch
    link home/.config/fontconfig .config/fontconfig

    link home/.config/niri/config.kdl .config/niri/config.kdl
    if command -v niri >/dev/null && ! niri validate -c "$HOME/.config/niri/config.kdl" >/dev/null 2>&1; then
        note "niri config does not validate: niri validate -c ~/.config/niri/config.kdl"
    fi

    link home/.config/foot/foot.ini .config/foot/foot.ini
    [ -f "$HOME/.config/foot/dank-colors.ini" ] || : > "$HOME/.config/foot/dank-colors.ini"
    link home/.config/xdg-terminals.list .config/xdg-terminals.list
    link home/.config/gtk-3.0/settings.ini .config/gtk-3.0/settings.ini
    copy_once home/.config/Thunar/uca.xml .config/Thunar/uca.xml
    copy_once home/.config/mimeapps.list .config/mimeapps.list
    ini_default "$HOME/.config/featherpad/fp.conf" text darkColorScheme true && done_ "FeatherPad dark editor"
    if command -v xfconf-query >/dev/null; then
        xfconf-query -c thunar -p /misc-window-title-style -n -t string \
            -s THUNAR_WINDOW_TITLE_STYLE_FULL_PATH_WITH_THUNAR_SUFFIX 2>/dev/null && done_ "Thunar: full path in title"
    fi
    if command -v gsettings >/dev/null; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark 2>/dev/null || true
        done_ "dark mode (adw-gtk3-dark)"
    fi
    local gtksh=/usr/share/quickshell/dms/scripts/gtk.sh
    if [ -f "$gtksh" ] && [ -f "$HOME/.config/gtk-3.0/dank-colors.css" ]; then
        bash "$gtksh" "$HOME/.config" apply >/dev/null 2>&1 && { bash "$gtksh" "$HOME/.config" patch false >/dev/null 2>&1 || true; } \
            && done_ "GTK apps follow the DMS colours"
    fi

    local f src dst
    for f in "${HIDE_DESKTOP[@]}"; do
        src=/usr/share/applications/$f.desktop dst=$HOME/.local/share/applications/$f.desktop
        [ -f "$src" ] || continue
        if [ -f "$dst" ] && grep -q '^NoDisplay=true' "$dst"; then continue; fi
        sed '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' "$src" > "$dst"
    done
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    done_ "launcher: helper entries hidden"

    local font_dir="$HOME/.local/share/fonts" tmp
    mkdir -p "$font_dir"
    if [ ! -f "$font_dir/JetBrainsMonoNerdFont-Regular.ttf" ]; then
        tmp=$(mktemp -d)
        if gh_release_asset ryanoasis/nerd-fonts 'JetBrainsMono\.tar\.xz' "$tmp/jb.tar.xz" \
           && tar -xJf "$tmp/jb.tar.xz" -C "$font_dir" --wildcards '*.ttf' \
           && [ -f "$font_dir/JetBrainsMonoNerdFont-Regular.ttf" ]; then
            fc-cache -f >/dev/null 2>&1 || true
            done_ "JetBrainsMono Nerd Font (installed, SHA-256 checked)"
        else note "JetBrainsMono Nerd Font: download failed; retried on next run"; fi
        rm -rf "$tmp"
    else done_ "JetBrainsMono Nerd Font"; fi

    local lsp="$HOME/.local/share/org.localsend.localsend_app/shared_preferences.json"
    if python3 -I - "$lsp" <<'EOF'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
if d.get("flutter.ls_minimize_to_tray") is True:
    sys.exit(0)
d["flutter.ls_minimize_to_tray"] = True
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"))
sys.exit(1)
EOF
    then done_ "LocalSend: close to tray"
    else done_ "LocalSend: close to tray (updated)"; fi

    # DMS settings: applied once
    local ds="$HOME/.config/dms/settings.json" dmark="$HOME/.local/state/niridesk/dms-settings.applied"
    mkdir -p "$HOME/.config/dms" "${dmark%/*}"
    if [ ! -f "$dmark" ]; then
        if [ -f "$ds" ]; then
            python3 -I - "$ds" "$HERE/home/.config/dms/settings.json" <<'EOF'
import json, sys
live, ours = sys.argv[1:]
d = json.load(open(live)); d.update(json.load(open(ours)))
json.dump(d, open(live, "w"), indent=2)
EOF
        else cp "$HERE/home/.config/dms/settings.json" "$ds"; fi
        touch "$dmark" && done_ "DMS settings (applied once)"
    else done_ "DMS settings (live ones kept)"; fi
    local dv
    dv=$(rpm -q --qf '%{VERSION}' dms 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+') || dv=""
    if [ -n "$dv" ] && [ ! -e "$HOME/.config/dms/.changelog-$dv" ]; then
        echo "$dv" > "$HOME/.config/dms/.changelog-$dv" && done_ "DMS $dv welcome page (marked as seen)"
    fi

    link home/.config/dms/plugins/OpenHere .config/dms/plugins/OpenHere
    local ps="$HOME/.config/dms/plugin_settings.json" psr=0
    python3 -I - "$ps" openHere 2>/dev/null <<'PYEOF' || psr=$?
import json, os, sys
f, pid = sys.argv[1:]
d = json.load(open(f)) if os.path.isfile(f) and os.path.getsize(f) else {}
if "enabled" in d.get(pid, {}):
    sys.exit(2)
d.setdefault(pid, {})["enabled"] = True
json.dump(d, open(f, "w"), indent=2)
PYEOF
    if [ "$psr" = 0 ]; then
        dms ipc call plugin-scan scan >/dev/null 2>&1 && sleep 1 && dms ipc call plugins enable openHere >/dev/null 2>&1 || true
        done_ "Open Here plugin enabled (updated)"
    elif [ "$psr" = 2 ]; then done_ "Open Here plugin enabled"; fi

    link home/.local/bin/open-here-cwd .local/bin/open-here-cwd
    link home/.local/bin/open-here-toolbox .local/bin/open-here-toolbox
    link home/.local/bin/open-with .local/bin/open-with
    link home/.local/share/applications/open-with.desktop .local/share/applications/open-with.desktop
    link home/.local/bin/screenshot-notify .local/bin/screenshot-notify
    link home/.local/bin/kbd-light .local/bin/kbd-light

    [ -f "$HERE/.extras" ] && bash "$HERE/extras.sh" home
    return 0
}

steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(system home)
for s in "${steps[@]}"; do
    case "$s" in
        system|home) "do_$s" ;;
        *) echo "unknown step: $s (system, home)" >&2; exit 2 ;;
    esac
done
say "done"
