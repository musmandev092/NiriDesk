# NiriDesk shell defaults

alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias pkg='sudo dnf'

info() {
    fastfetch "$@"
}

cls() {
    printf '\033[2J\033[3J\033[H'
    info 2>/dev/null
}

# free disk space; --deep also checks btrfs
clean() {
    local deep=0
    case ${1:-} in
        '') ;;
        --deep|--deeply|-d) deep=1 ;;
        *) printf 'Usage: clean [--deep|--deeply|-d]\n'; return 1 ;;
    esac

    printf 'This removes package caches, old logs, crash dumps, caches and trash.\n'
    (( deep )) && printf 'Deep mode: also btrfs scrub + light balance (takes a few minutes).\n'
    printf 'Continue? [y/N] '
    local answer
    read -r answer
    [[ $answer =~ ^[Yy]$ ]] || return 0

    local before after
    before=$(df --output=avail -B1 / | tail -1)

    echo '==> dnf package cache'
    sudo dnf clean all

    echo '==> Unused dependencies'
    sudo dnf autoremove -y

    if command -v flatpak >/dev/null; then
        echo '==> Unused Flatpak runtimes (user + system)'
        flatpak uninstall --user --unused -y 2>/dev/null || true
        flatpak uninstall --system --unused -y 2>/dev/null || true
    fi

    echo '==> System logs (keep 7 days, max 200M)'
    sudo journalctl --vacuum-time=7d --vacuum-size=200M

    echo '==> Crash dumps older than 7 days'
    sudo find /var/lib/systemd/coredump -type f -mtime +7 -delete

    if command -v podman >/dev/null; then
        echo '==> Unused podman images (containers are never touched)'
        podman image prune -f >/dev/null 2>&1 || true
    fi

    echo '==> Brave cache'
    if pgrep -f brave-origin >/dev/null; then
        echo '    skipped: Brave is open (close it to clean its cache)'
    else
        command rm -rf "$HOME/.cache/BraveSoftware"
    fi

    echo '==> Thumbnails and trash'
    command rm -rf "$HOME/.cache/thumbnails"
    if command -v gio >/dev/null; then
        gio trash --empty
    fi

    if (( deep )); then
        echo '==> Btrfs scrub (checks every block against its checksum)'
        sudo btrfs scrub start -B /
        echo '==> Btrfs light balance (repacks nearly-empty data chunks)'
        sudo btrfs balance start -dusage=10 /
        echo '==> Btrfs error counters (all should be 0)'
        sudo btrfs device stats /
    fi

    after=$(df --output=avail -B1 / | tail -1)
    printf '==> Done. Freed: %s\n' "$(numfmt --to=iec $(( after > before ? after - before : 0 )))"
}

# prompt: folder, git, toolbox, duration (>= 2 s), exit code
if [[ $- == *i* ]]; then
    __nd_gp=/usr/share/git-core/contrib/completion/git-prompt.sh
    [[ -r $__nd_gp ]] && . "$__nd_gp"
    unset __nd_gp
    GIT_PS1_SHOWDIRTYSTATE=1
    GIT_PS1_SHOWSTASHSTATE=1
    GIT_PS1_SHOWUNTRACKEDFILES=1
    GIT_PS1_SHOWUPSTREAM="verbose"
    GIT_PS1_SHOWCONFLICTSTATE=yes
    GIT_PS1_HIDE_IF_PWD_IGNORED=1
    GIT_PS1_STATESEPARATOR=" "

    # toolbox name
    __nd_box=
    if [[ -f /run/.containerenv ]]; then
        while IFS= read -r __nd_l; do
            [[ $__nd_l == name=* ]] && { __nd_box=${__nd_l#name=}; __nd_box=${__nd_box//\"/}; }
        done < /run/.containerenv
        unset __nd_l
        [[ -n $__nd_box ]] || __nd_box=container
    fi

    # branch from .git/HEAD when git-prompt.sh is missing
    __nd_head() {
        local d=$PWD h
        while [[ -n $d ]]; do
            if [[ -f $d/.git/HEAD ]]; then
                read -r h < "$d/.git/HEAD"
                [[ $h == ref:* ]] && printf -v __nd_git '%s' "${h##*/}" || printf -v __nd_git '%s' "${h:0:7}"
                return
            fi
            d=${d%/*}
        done
    }

    __nd_prompt() {
        local rc=$? now dt
        # text only; PS1 references these so branch names are never expanded
        __nd_gs='' __nd_ts='' __nd_rs='' __nd_ac=$'\e[1;32m'
        if [[ -n ${__nd_t0:-} ]]; then
            now=${EPOCHREALTIME//[!0-9]/}
            dt=$(( (now - __nd_t0) / 1000 ))   # milliseconds
            if (( dt >= 60000 )); then __nd_ts="  $((dt / 60000))m$(((dt / 1000) % 60))s"
            elif (( dt >= 2000 )); then __nd_ts="  $((dt / 1000)).$(((dt / 100) % 10))s"; fi
            if (( rc != 0 )); then __nd_rs="  ✘ $rc"; __nd_ac=$'\e[1;31m'; fi
            unset __nd_t0
        fi

        local git=''
        if declare -F __git_ps1 >/dev/null; then
            git=$(__git_ps1 '%s')
        else
            __nd_git=; __nd_head; git=$__nd_git
        fi
        if [[ -n $git ]]; then
            # u+N-M -> ↑N↓M
            if [[ $git =~ ^(.*)[\ |]u([=+-][0-9+-]*)(.*)$ ]]; then
                local head=${BASH_REMATCH[1]} up=${BASH_REMATCH[2]} tail=${BASH_REMATCH[3]} a='' b=''
                [[ $up =~ \+([0-9]+) ]] && a="↑${BASH_REMATCH[1]}"
                [[ $up =~ -([0-9]+) ]] && b="↓${BASH_REMATCH[1]}"
                git="$head${a}${b}"; [[ -n $a$b ]] && git="$head $a$b"
                git+=$tail
            fi
            __nd_gs="  $git"
        fi
        return "$rc"
    }
    __nd_bs=${__nd_box:+  ⬢ $__nd_box}
    PS1='\[\e[1;36m\]\w\[\e[1;35m\]${__nd_gs}\[\e[1;34m\]${__nd_bs}\[\e[0;33m\]${__nd_ts}\[\e[1;31m\]${__nd_rs}\[\e[0m\]\n\[${__nd_ac}\]❯\[\e[0m\] '

    # start time of each command
    PS0='${PS1:$((__nd_t0=${EPOCHREALTIME//[!0-9]/})):0}'
    if [[ ${PROMPT_COMMAND[*]:-} != *__nd_prompt* ]]; then
        PROMPT_COMMAND=(__nd_prompt "${PROMPT_COMMAND[@]}")
    fi
fi

if [[ $- == *i* ]] && [ ! -f /run/.toolboxenv ] && [ ! -f /run/.containerenv ]; then
    info 2>/dev/null
fi
