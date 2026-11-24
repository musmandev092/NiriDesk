# NiriDesk

Fedora 45 desktop on niri + DMS, installed from a kickstart ISO and kept in shape by `apply.sh`.

- niri + DMS shell, DMS login screen on niri
- Brave, foot, Thunar, FeatherPad, galculator, imv, mpv, GNOME Disks, btop, nano, LocalSend
- CUPS, firewalld, plymouth, SELinux enforcing, no SSH server
- NVIDIA detected automatically: pre-built `kmod-nvidia` + `nvidia` from [fedora-nvidia](https://github.com/musmandev092/fedora-nvidia), no akmod
- Optional in the installer (Software → Extras): toolbox, Chromium, Edge, VS Code, GitHub CLI, Claude Code, Codex, Antigravity, Cursor, OpenCode and Herdr (CLI and apps)

About 818 packages (833 with toolbox, +4 with NVIDIA).

## Install

```sh
install/build-iso.sh            # ISOs: erase disk, dual boot, VM
install/build-iso.sh toolbox    # same, toolbox preselected
install/build-iso.sh check      # installer tests + ksvalidator
```

On an existing Fedora 45:

```sh
./apply.sh                      # system + home
touch .toolbox && ./apply.sh system
echo chromium >> .extras && ./apply.sh   # see ./extras.sh list
```

## Keys

| Keys | Action |
|---|---|
| Super+Return / E / B | foot / Thunar / Brave |
| Super+Space | Launcher |
| Super+K | All shortcuts |
| Super+Q | Close |
| Super+F / Shift+F | Maximize / fullscreen |
| Super+Shift+T | Float |
| Super+A / D | Focus left / right |
| Super+W / S | Workspace up / down |
| Super+Tab, Alt+Tab | Overview, recent windows |
| Super+Z | Open Here |
| Print, Super+Shift+S | Screenshot |

## Tests

```sh
cd install/tui && python3 -m unittest discover -s tests
```

VM tests: `install/vm-install.py`, `vm-boot-test.py`, `vm-run.py vm-checks.sh`.
