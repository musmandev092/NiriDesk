#!/bin/bash
# Optional extras listed in .extras (one per line).
# Usage: extras.sh system|home|list
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/.extras"
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
done_() { printf '    \033[32mok\033[0m  %s\n' "$*"; }
note() { printf '    \033[33m!!\033[0m  %s\n' "$*"; }
fetch() { curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 --connect-timeout 15 "$@"; }

SYSTEM_EXTRAS="chromium edge claude-app codex-app cursor-app opencode-app"
HOME_EXTRAS="claude-code codex-cli antigravity-cli cursor-cli opencode-cli herdr-cli herdr-app antigravity-app"
ANTIGRAVITY_URL=https://storage.googleapis.com/antigravity-public/antigravity-hub/2.34.0-5887025308631040/linux-x64/Antigravity.tar.gz

SUDO=sudo; [ "$(id -u)" -eq 0 ] && SUDO=""
wanted() { [ -f "$LIST" ] && grep -qxF "$1" "$LIST"; }

dnf_install() {
    local p missing=()
    for p in "$@"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
    [ ${#missing[@]} -eq 0 ] && return 0
    $SUDO dnf -y -q --setopt=install_weak_deps=False install "${missing[@]}"
}

repo_put() {
    cmp -s "$HERE/etc/yum.repos.d/$1" "/etc/yum.repos.d/$1" 2>/dev/null && return 0
    $SUDO install -m 0644 "$HERE/etc/yum.repos.d/$1" "/etc/yum.repos.d/$1"
}

# latest GitHub release asset matching a regex, checked against its sha256 digest
gh_asset() {
    local repo=$1 pat=$2 out=$3 rel name url sum
    rel=$(fetch "https://api.github.com/repos/$repo/releases/latest") || return 1
    read -r name url sum < <(python3 -I -c '
import json, re, sys
pat = re.compile(sys.argv[1])
for a in json.load(sys.stdin).get("assets", []):
    if pat.fullmatch(a["name"]) and (a.get("digest") or "").startswith("sha256:"):
        print(a["name"], a["browser_download_url"], a["digest"][7:]); break' "$pat" <<<"$rel") || return 1
    [ -n "${name:-}" ] || return 1
    fetch -o "$out" "$url" || return 1
    echo "$sum  $out" | sha256sum -c --status
}

x_chromium() {
    dnf_install chromium
    local cc=/etc/chromium/chromium.conf blk
    [ -f "$cc" ] || return 0
    blk=$(printf '# >>> niridesk: Google sign-in >>>\n%s\n# <<< niridesk <<<' "$(cat "$HERE/etc/chromium/chromium.conf.d-niridesk")")
    if [ "$(sed -n '/^# >>> niridesk:/,/^# <<< niridesk <<<$/p' "$cc")" != "$blk" ]; then
        $SUDO sed -i '/^# >>> niridesk:/,/^# <<< niridesk <<<$/d' "$cc"
        printf '%s\n' "$blk" | $SUDO tee -a "$cc" >/dev/null
    fi
    done_ "Chromium (sign-in keys from ~/.config/chromium-flags.conf)"
}

x_edge() {
    rpm -q gpg-pubkey --qf '%{SUMMARY}\n' 2>/dev/null | grep -q Microsoft || $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
    repo_put microsoft-edge.repo
    dnf_install microsoft-edge-stable && done_ "Microsoft Edge"
}

x_claude-app() { dnf_install claude-desktop && done_ "Claude Desktop"; }

x_cursor-app() {
    rpm -q gpg-pubkey --qf '%{SUMMARY}\n' 2>/dev/null | grep -qi anysphere || $SUDO rpm --import https://downloads.cursor.com/keys/anysphere.asc
    repo_put cursor.repo
    dnf_install cursor && done_ "Cursor"
}

x_codex-app() {
    rpm -q chatgpt >/dev/null 2>&1 && { done_ "Codex app"; return; }
    local tmp; tmp=$(mktemp -d)
    fetch -o "$tmp/chatgpt.x86_64.rpm" https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm \
        && $SUDO dnf -y -q --setopt=install_weak_deps=False install "$tmp/chatgpt.x86_64.rpm" && done_ "Codex app"
    rm -rf "$tmp"
}

x_opencode-app() {
    rpm -qa --qf '%{NAME}\n' | grep -qi '^opencode' && { done_ "OpenCode app"; return; }
    local tmp; tmp=$(mktemp -d)
    if gh_asset anomalyco/opencode 'opencode-desktop-linux-x86_64\.rpm' "$tmp/opencode.rpm"; then
        $SUDO dnf -y -q --setopt=install_weak_deps=False install "$tmp/opencode.rpm" && done_ "OpenCode app (SHA-256 checked)"
    else note "OpenCode app: download or check failed"; fi
    rm -rf "$tmp"
}

x_claude-code() { command -v claude >/dev/null || fetch https://claude.ai/install.sh | bash; done_ "Claude Code"; }
x_antigravity-cli() { command -v agy >/dev/null || fetch https://antigravity.google/cli/install.sh | bash; done_ "Antigravity CLI"; }
x_cursor-cli() { command -v agent >/dev/null || fetch https://cursor.com/install | bash; done_ "Cursor CLI"; }
x_opencode-cli() { command -v opencode >/dev/null || fetch https://opencode.ai/install | bash; done_ "OpenCode CLI"; }
x_herdr-cli() { command -v herdr >/dev/null || fetch https://herdr.dev/install.sh | sh; done_ "Herdr"; }
x_herdr-app() { command -v herdr-app >/dev/null || fetch https://releases.herdr.dev/app/install.sh | sh; done_ "Herdr app"; }

x_codex-cli() {
    [ -x "$HOME/.local/bin/codex" ] && { done_ "Codex CLI"; return; }
    local tmp; tmp=$(mktemp -d)
    if gh_asset openai/codex 'codex-x86_64-unknown-linux-musl\.tar\.gz' "$tmp/codex.tgz" \
       && tar -xzf "$tmp/codex.tgz" -C "$tmp" && install -D -m 755 "$tmp/codex-x86_64-unknown-linux-musl" "$HOME/.local/bin/codex"; then
        done_ "Codex CLI (SHA-256 checked)"
    else note "Codex CLI: download or check failed"; fi
    rm -rf "$tmp"
}

x_antigravity-app() {
    local dir="$HOME/.local/share/antigravity" tmp size got
    [ -x "$dir/antigravity" ] && { done_ "Antigravity app"; return; }
    tmp=$(mktemp -d)
    size=$(curl -fsSIL "$ANTIGRAVITY_URL" | tr -d '\r' | sed -n 's/^content-length: //Ip' | tail -n1)
    if fetch -o "$tmp/ag.tgz" "$ANTIGRAVITY_URL" && got=$(stat -c %s "$tmp/ag.tgz") && [ "$got" = "$size" ] \
       && tar -tzf "$tmp/ag.tgz" >/dev/null && tar -xzf "$tmp/ag.tgz" -C "$tmp"; then
        rm -rf "$dir" && mv "$tmp/Antigravity-x64" "$dir"
        mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
        ln -sfn "$dir/antigravity" "$HOME/.local/bin/antigravity"
        printf '[Desktop Entry]\nType=Application\nName=Antigravity\nExec=%s %%U\nIcon=antigravity\nCategories=Development;\nStartupWMClass=Antigravity\n' \
            "$dir/antigravity" > "$HOME/.local/share/applications/antigravity.desktop"
        done_ "Antigravity app"
    else note "Antigravity app: download failed"; fi
    rm -rf "$tmp"
}

run() {
    local x
    for x in $1; do
        wanted "$x" || continue
        "x_$x" || note "$x: failed; retried on next run"
    done
}

case "${1:-}" in
    system) say "extras (system)"; run "$SYSTEM_EXTRAS" ;;
    home)   say "extras (home)"; mkdir -p "$HOME/.local/bin"; run "$HOME_EXTRAS" ;;
    list)   echo "available: $SYSTEM_EXTRAS $HOME_EXTRAS"; echo "selected: $(tr '\n' ' ' < "$LIST" 2>/dev/null)" ;;
    *) echo "usage: extras.sh system|home|list" >&2; exit 2 ;;
esac
