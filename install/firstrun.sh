#!/bin/bash
# first login: finish home setup, link the login screen
set -u
repo="$HOME/Projects/NiriDesk"
state="$HOME/.local/state/niridesk"
log="$state/firstrun.log"
mkdir -p "$state"
notify() { notify-send -a "NiriDesk" "$@" 2>/dev/null || true; }

session_env() {
    local i line
    for i in $(seq 120); do
        while IFS= read -r line; do
            case $line in WAYLAND_DISPLAY=*|NIRI_SOCKET=*|XDG_CURRENT_DESKTOP=*|DBUS_SESSION_BUS_ADDRESS=*) export "${line?}" ;; esac
        done < <(systemctl --user show-environment 2>/dev/null)
        [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${NIRI_SOCKET:-}" ] && return 0
        if [ -z "${NIRI_SOCKET:-}" ]; then
            NIRI_SOCKET=$(ls "/run/user/$UID"/niri.*.sock 2>/dev/null | head -n1); [ -n "$NIRI_SOCKET" ] && export NIRI_SOCKET
        fi
        if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -S "/run/user/$UID/wayland-1" ]; then export WAYLAND_DISPLAY=wayland-1; fi
        [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${NIRI_SOCKET:-}" ] && return 0
        sleep 1
    done
    return 1
}
session_env || echo "$(date -Is) no niri session found; notifications and the greeter step may not show" >> "$state/firstrun-session.log"

rc=0
if [ ! -e "$state/firstrun.done" ]; then
    for _ in $(seq 36); do
        curl -fsS -o /dev/null --max-time 5 https://fedoraproject.org/ && break
        sleep 5
    done
    notify "Setting up NiriDesk" "Finishing your desktop: a minute or two. You can keep working."
    if "$repo/apply.sh" home > "$log" 2>&1; then
        touch "$state/firstrun.done"
        notify "NiriDesk is ready" "Everything is set up. Log: $log"
    else
        rc=1
        notify -u critical "Setup did not finish" "See $log. It retries at the next login, or run $repo/apply.sh home"
    fi

    nv=0
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
        case $(cat "$d/class" 2>/dev/null) in 0x0300*|0x0302*) nv=1 ;; esac
    done
    if [ "$nv" = 1 ] && ! rpm -q "kmod-nvidia-$(uname -r)" >/dev/null 2>&1; then
        notify -u critical "NVIDIA driver missing" "No driver for kernel $(uname -r) yet. Run: niridesk-nvidia-sync"
    fi
fi

if [ ! -e "$state/greeter-sync.done" ]; then
    if ! command -v dms-greeter >/dev/null; then
        touch "$state/greeter-sync.done"
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
        notify "Login screen" "Enter your password once so the login screen follows your wallpaper and theme."
        foot -T "NiriDesk: link login screen" bash -c \
            "DMS_PRIVESC=sudo dms-greeter sync --yes && touch '$state/greeter-sync.done'; echo; read -rp 'Press Enter to close' _" || true
    fi
fi

exit "$rc"
