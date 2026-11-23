#!/bin/bash
s() { echo test | sudo -S "$@" 2>/dev/null; }
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; }
chk() { local what=$1; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi; }
tb=0; [ -e ~/Projects/NiriDesk/.toolbox ] && tb=1
echo "## toolbox: $([ "$tb" = 1 ] && echo yes || echo no)"

echo "## system"
echo "  kernel $(uname -r), $(rpm -qa | wc -l) packages, target $(systemctl get-default)"
chk "disk is LUKS-encrypted"            sh -c 'lsblk -o FSTYPE | grep -q crypto_LUKS'
chk "root is btrfs"                     sh -c 'findmnt -no FSTYPE / | grep -qx btrfs'
chk "no failed services"                sh -c '[ -z "$(systemctl --failed --no-legend)" ]'
pend=$(s dnf -q check-upgrade | grep -cE '\.(x86_64|noarch)')
chk "fully updated ($pend pending)"     test "$pend" -eq 0
echo "  niri $(rpm -q --qf '%{VERSION}' niri), kernels: $(rpm -q kernel | tr '\n' ' ')"
echo "  NVIDIA modules for: $(rpm -qa --qf '%{NAME}\n' 'kmod-nvidia-*' | sed 's/^kmod-nvidia-//' | tr '\n' ' ')"
systemctl --failed --no-legend | sed 's/^/        /'

echo "## desktop"
chk "login screen (greetd) running"     systemctl is-active greetd
chk "quickshell is 0.3+ (DMS build)"    sh -c 'rpm -q quickshell | grep -q "^quickshell-0\.[3-9]"'
chk "niri installed"                    rpm -q niri
chk "Fedora copies of DMS deps hidden"  test -f /etc/dnf/repos.override.d/50-dms-copr.repo
for p in quickshell dux-search dux-gop matugen dms dux-greeter niri xwayland-satellite; do printf '        %s\n' "$(rpm -q "$p")"; done

echo "## apps"
for p in brave-origin foot Thunar featherpad galculator imv mpv gnome-disk-utility btop nano cups cups-pk-helper firewalld; do
    chk "$p" rpm -q "$p"
done
for p in chromium microsoft-edge-stable powershell; do
    chk "$p absent (personal setup only)" sh -c "! rpm -q $p"
done
if [ "$tb" = 1 ]; then chk "toolbox" rpm -q toolbox; else chk "toolbox absent" sh -c '! rpm -q toolbox'; fi
chk "LocalSend in /opt"                 test -x /opt/localsend/localsend_app

echo "## security"
chk "desktop app repo is signed"        grep -qx 'gpgcheck=1' /etc/yum.repos.d/claude-desktop.repo
chk "no Microsoft repos"               sh -c '! ls /etc/yum.repos.d/microsoft-*.repo'
chk "no SSH server"                     sh -c '! rpm -q openssh-server'
fw=$(s firewall-cmd --list-all)
chk "firewall: no http/https"           sh -c '! printf "%s\n" "$1" | grep -E "^ *services:" | grep -qwE "http|https"' _ "$fw"
chk "firewall: SSH closed"              sh -c '! printf "%s\n" "$1" | grep -E "^ *services:" | grep -qw ssh' _ "$fw"
chk "firewall: no SSH rate-limit rule"  sh -c '! printf "%s\n" "$1" | grep -q "limit value"' _ "$fw"
chk "firewall: LocalSend 53317 tcp+udp" sh -c 'printf "%s\n" "$1" | grep -E "^ *ports:" | grep -q "53317/tcp" && printf "%s\n" "$1" | grep -E "^ *ports:" | grep -q "53317/udp"' _ "$fw"
chk "sudoless installed"                test -x /usr/local/bin/sudoless
chk "no SSH server running"           sh -c '! systemctl is-active -q sshd 2>/dev/null'
chk "no backups beside live files"      sh -c '! ls /etc/yum.repos.d/*.bak /usr/local/bin/*.bak '
chk "no sway / ssh server / nvidia-settings" sh -c '! rpm -q sway && ! rpm -q openssh-server && ! rpm -q nvidia-settings'

echo "## repos"
ls /etc/yum.repos.d/ | sed 's/^/        /'
chk "dnf sees all repos (refresh)"      s dnf -q makecache

echo "## kickstart %post"
s tail -4 /root/ks-post.log | sed 's/^/        /'
s cat /root/ks-done | sed 's/^/        /'
