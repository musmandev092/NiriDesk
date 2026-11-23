#!/bin/bash
s() { echo test | sudo -S "$@" 2>/dev/null; }
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; }
chk() { local w=$1; shift; if "$@" >/dev/null 2>&1; then ok "$w"; else bad "$w"; fi; }
state=~/.local/state/niridesk
tb=0; [ -e ~/Projects/NiriDesk/.toolbox ] && tb=1
echo "## toolbox: $([ "$tb" = 1 ] && echo yes || echo no)"

echo "## answers became the system"
chk "computer name is vmtest"          sh -c '[ "$(hostname)" = vmtest ]'
chk "time zone Asia/Karachi"           sh -c 'timedatectl show -p Timezone --value | grep -qx Asia/Karachi'
chk "user is an administrator (wheel)" sh -c 'id -nG | grep -qw wheel'
chk "full name Test User"              sh -c 'getent passwd test | cut -d: -f5 | grep -q "Test User"'
chk "no passphrase in saved kickstart" sh -c '! echo test | sudo -S grep -q passphrase /root/anaconda-ks.cfg'
chk "no secrets in logs or kickstarts" sh -c '! echo test | sudo -S grep -rIsqE -- "passphrase=|--plaintext|password=test" /root /var/log/anaconda'
chk "no kickstart fragments kept"      sh -c '[ -z "$(echo test | sudo -S find /root /var/log /etc -name "ks-machine.cfg" 2>/dev/null)" ]'
chk "settings saved without secrets"   sh -c 'c=$(echo test | sudo -S cat /root/niridesk-config.json) && printf "%s" "$c" | grep -q "\"password\": \"set\"" && ! printf "%s" "$c" | grep -qE "[$](y|6)[$]"'
chk "settings file is root-only"       sh -c '[ "$(echo test | sudo -S stat -c %a /root/niridesk-config.json)" = 600 ]'
chk "installer choices applied"        sh -c 'echo test | sudo -S grep -qx "ADMIN=test" /root/niridesk-choices.env'

echo "## installer did the system part"
chk "NiriDesk copied to ~/Projects"    test -x ~/Projects/NiriDesk/apply.sh
chk "NiriDesk owned by the user"       sh -c '[ "$(stat -c %U ~/Projects/NiriDesk/apply.sh)" = test ]'
chk "GRUB font"                        grep -qx 'GRUB_FONT=/boot/grub2/fonts/adwaita-mono-48.pf2' /etc/default/grub
chk "greetd running"                   systemctl is-active greetd
chk "fully updated"                    sh -c '[ "$(echo test | sudo -S dnf -q check-upgrade 2>/dev/null | grep -cE "\.(x86_64|noarch)")" -eq 0 ]'
chk "no Chromium (extra only)" sh -c '! rpm -q chromium'
if [ "$tb" = 1 ]; then chk "toolbox installed" rpm -q toolbox; else chk "no toolbox" sh -c '! rpm -q toolbox'; fi
chk "login screen on niri"             grep -q -- '--command niri' /etc/greetd/config.toml
s tail -3 /root/ks-post-nochroot.log | sed 's/^/        /'

echo "## first login: home setup runs by itself"
chk "first-run service enabled"        test -L ~/.config/systemd/user/default.target.wants/niridesk-firstrun.service
echo "  waiting for it to finish (up to 25 min) ..."
for _ in $(seq 150); do
    [ -f "$state/firstrun.done" ] && break
    systemctl --user is-active -q niridesk-firstrun.service || { [ -f "$state/firstrun.log" ] && break; }
    sleep 10
done
chk "first-run finished (done marker)" test -f "$state/firstrun.done"
grep -E 'ok|!!|mason:|treesitter:' "$state/firstrun.log" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g; s/^/        /' | tail -40
chk "custom.sh linked"                 test -L ~/.bashrc.d/custom.sh
chk "starship"                         ~/.local/bin/starship --version
chk "JetBrainsMono Nerd Font"          test -f ~/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf
chk "niri config linked"              test -L ~/.config/niri/config.kdl
chk "DMS welcome page marked seen"     sh -c 'ls ~/.config/dms/.changelog-* >/dev/null'
chk "Switcher plugin linked"           test -L ~/.config/dms/plugins/Switcher
chk "OpenHere plugin linked"           test -L ~/.config/dms/plugins/OpenHere
chk "DMS running"                     pgrep -f 'dms run'
chk "Open Here plugin enabled"        grep -q '"openHere"' ~/.config/dms/plugin_settings.json
chk "simple bash linked"              test -L ~/.bashrc.d/niridesk.sh
chk "niri config valid"               niri validate -c ~/.config/niri/config.kdl
chk "no dev container by default"     sh -c '! podman container exists dev 2>/dev/null'
