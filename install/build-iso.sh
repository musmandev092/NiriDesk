#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/VMs/fedora-iso"
TUI="$HERE/tui"
KS="$HERE/ks.cfg"
KS_DUAL="$HERE/ks-dualboot.cfg"
MODE=${1:-build}
case "$MODE" in build|toolbox|check) ;; *) echo "usage: build-iso.sh [build|toolbox|check]" >&2; exit 2 ;; esac

unit_tests() {
    local log rc=0
    log=$(cd "$TUI" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests 2>&1) || rc=$?
    [ "$rc" = 0 ] || { printf '%s\n' "$log" >&2; echo "installer unit tests failed" >&2; return 1; }
    echo "installer unit tests: $(grep -oE 'Ran [0-9]+ tests' <<<"$log"), OK"
}

validate() {
    command -v ksvalidator >/dev/null || { echo "ksvalidator not found: sudo dnf install pykickstart" >&2; return 1; }
    local ver=F45 out=/tmp/niridesk s ks fixture preset n=0
    grep -qw F45 <<<"$(ksvalidator -l 2>/dev/null)" || ver=DEVEL
    for s in "$TUI"/tests/answers/*.json; do
        read -r fixture preset < <(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d.get("fixture", "vm"), d.get("preset", "clean"))' "$s")
        rm -rf "$out"
        python3 -I -B "$TUI/run.py" --dry-run --fixtures "$fixture" --preset "$preset" \
            --answers "$s" --out "$out" >/dev/null || { echo "sample $(basename "$s") failed" >&2; return 1; }
        for ks in "$@"; do ksvalidator -v "$ver" "$ks" || { echo "with sample $(basename "$s")" >&2; return 1; }; done
        n=$((n + 1))
    done
    rm -rf "$out"
    echo "kickstarts valid ($ver) with $n rendered samples"
}

url_ok() { [[ $2 =~ $3 ]] || { echo "$1 must be an $4 URL" >&2; exit 2; }; }
HTTPS='^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._/-]*)?$'
[ -z "${MIRROR:-}" ] || { url_ok MIRROR "$MIRROR" "$HTTPS" https; MIRROR=${MIRROR%/}; }
[ -z "${COPR_CACHE:-}" ] || { url_ok COPR_CACHE "$COPR_CACHE" '^https?://[A-Za-z0-9.:-]+(/[A-Za-z0-9._/-]*)?$' "http(s)"; COPR_CACHE=${COPR_CACHE%/}; }

unit_tests
validate "$KS" "$KS_DUAL"
[ "$MODE" = check ] && exit 0

SRC=""
for f in "$DIR"/Fedora-Everything-netinst-x86_64-45*.iso; do [ -f "$f" ] && SRC=$f; done
[ -n "$SRC" ] || { echo "missing $DIR/Fedora-Everything-netinst-x86_64-45*.iso (download and verify it first)" >&2; exit 1; }
command -v mkksiso >/dev/null || { echo "mkksiso not found: sudo dnf install lorax" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
rsync -a --exclude='target/' --exclude='.git/' --exclude='__pycache__/' --exclude='*.log' \
      --exclude='*.bak' --exclude='*.bak.*' --exclude='/.toolbox' --exclude='/.claude/' "$HERE/../" "$STAGE/NiriDesk/"
T="$STAGE/NiriDesk/install/tui"

TOOLBOX=false; [ "$MODE" = toolbox ] && TOOLBOX=true
TOOLBOX=$TOOLBOX FEDORA="${MIRROR:-}" CACHE="${COPR_CACHE:-}" python3 -c '
import json, os, sys
json.dump({"toolbox": os.environ["TOOLBOX"] == "true", "fedora": os.environ["FEDORA"],
           "copr_cache": os.environ["CACHE"]}, open(sys.argv[1], "w"), indent=2)' "$T/build.json"
echo "installer defaults: $(tr -d '\n' < "$T/build.json")"

if [ "${PKGINDEX:-1}" = 1 ]; then
    if dnf repoquery -q --repo=fedora --repo=updates --latest-limit=1 --arch=x86_64,noarch \
           --queryformat $'%{name}\t%{summary}\t%{repoid}\t%{downloadsize}\n' 2>/dev/null | sort -u | gzip -9 > "$T/pkgindex.tsv.gz" \
       && [ "$(gzip -dc "$T/pkgindex.tsv.gz" | head -c 1 | wc -c)" = 1 ]; then
        echo "package index: $(gzip -dc "$T/pkgindex.tsv.gz" | wc -l) names"
    else
        rm -f "$T/pkgindex.tsv.gz"
        echo "package index: not built (dnf repoquery failed); extra packages are installed best effort"
    fi
fi

command -v implantisomd5 >/dev/null || { echo "implantisomd5 not found: sudo dnf install isomd5sum" >&2; exit 1; }

# No inst.updates: Ventoy rewrites inst.stage2 and inst.ks to its device, but not other hd:LABEL= paths.
iso() {
    local tmp="$STAGE/$3" cfg
    mkksiso --skip-mkefiboot --no-md5sum --ks "$STAGE/NiriDesk/install/$1" -a "$STAGE/NiriDesk" -c "$2" "$SRC" "$tmp"
    args=()
    for cfg in /EFI/BOOT/grub.cfg /boot/grub2/grub.cfg; do
        xorriso -osirrox on -indev "$tmp" -extract "$cfg" "$STAGE/menu.cfg" >/dev/null 2>&1 || continue
        chmod u+w "$STAGE/menu.cfg"
        sed -i -e 's/^set default="1"/set default="0"/' -e 's/^set timeout=60/set timeout=10/' \
               -e "s/'Install Fedora 45'/'Install NiriDesk'/" -e "s/'Test this media \& install Fedora 45'/'Test this media \& install NiriDesk'/" \
               "$STAGE/menu.cfg"
        cp "$STAGE/menu.cfg" "$STAGE/menu-${cfg//\//_}"
        args+=(-update "$STAGE/menu-${cfg//\//_}" "$cfg")
    done
    xorriso -indev "$tmp" -outdev "$DIR/$3" -boot_image any replay "${args[@]}" >/dev/null 2>&1
    implantisomd5 --force "$DIR/$3" >/dev/null
    rm -f "$tmp"
}

sfx=""; [ "$MODE" = toolbox ] && sfx=-toolbox
out=("niridesk-fedora45$sfx.iso" "niridesk-fedora45-dualboot$sfx.iso" "niridesk-fedora45-vm$sfx.iso")
for o in "${out[@]}"; do rm -f "${DIR:?}/$o"; done
iso ks.cfg "rhgb fbcon=font:TER16x32" "${out[0]}"
iso ks-dualboot.cfg "rhgb fbcon=font:TER16x32" "${out[1]}"
iso ks.cfg "fbcon=font:TER16x32 console=tty0 console=ttyS0,115200" "${out[2]}"
for o in "${out[@]}"; do ls -lh "$DIR/$o"; done
