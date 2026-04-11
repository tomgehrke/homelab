#!/usr/bin/env bash

# ==============================================================
# fancy-prompt.sh
#
# Makes your bash prompt fancy!
# Requires a Nerd Font or Powerline-patched font for segment arrows.
#
# NOTE: If colors seem off or adjacent characters don't blend
#       when they should, check your terminal to see if any
#       color/contrast correction is being automatically
#       applied. This is generally done to improve legibility
#       in certain cases.
# ==============================================================

# Powerline glyph — requires Nerd Font / Powerline-patched font
PL_R=$'\ue0b0'   #  solid right-pointing arrow

# Git support — degrade gracefully if .git-prompt is not yet linked
if [[ -f ~/.git-prompt ]]; then
    source ~/.git-prompt
else
    __git_ps1() { :; }
fi

GIT_PS1_SHOWDIRTYSTATE=yes
GIT_PS1_SHOWUNTRACKEDFILES=yes
GIT_PS1_SHOWUPSTREAM=auto
GIT_PS1_SHOWCONFLICTSTATE=yes

# Alert flag rendered as a prominent banner above the main prompt line.
# FP_LEVEL (1-5) and FP_FLAG can be exported at any time.
getFlag() {
    local level="$1" caption="$2"
    local r g b

    case "$level" in
        1) r=200; g=0;   b=0   ;;   # Red
        2) r=210; g=90;  b=0   ;;   # Orange
        3) r=190; g=180; b=0   ;;   # Yellow
        4) r=0;   g=170; b=170 ;;   # Cyan
        5) r=0;   g=70;  b=190 ;;   # Blue
        *) return 1 ;;
    esac

    local lum=$(( (2126 * r + 7152 * g + 722 * b) / 10000 ))
    local fg="0;0;0"
    (( lum < 100 )) && fg="255;255;255"

    printf '\n\001\e[1;48;2;%d;%d;%d;38;2;%sm\002 ⚑ %s \001\e[0m\002' \
        "$r" "$g" "$b" "$fg" "$caption"
}

getRGBValue() {
    local input="$1" length lowerThreshold=60 r=0 g=0 b=0
    length=${#input}

    if (( length == 0 )); then
        echo "${lowerThreshold};${lowerThreshold};${lowerThreshold}"
        return
    fi

    for (( i=0; i<length; i++ )); do
        local cv=$(printf "%d" "'${input:i:1}")
        r=$(( (r + cv)     % 200 ))
        g=$(( (g + cv * 2) % 200 ))
        b=$(( (b + cv * 3) % 200 ))
    done

    (( r < lowerThreshold )) && (( r += lowerThreshold ))
    (( g < lowerThreshold )) && (( g += lowerThreshold ))
    (( b < lowerThreshold )) && (( b += lowerThreshold ))

    echo "$r;$g;$b"
}

getLuminosity() {
    echo $(( (2126 * $1 + 7152 * $2 + 722 * $3) / 10000 ))
}

# Scale an "r;g;b" string so its brightest channel hits `target` (max 255).
boostRGB() {
    local rgb="$1" target="${2:-210}"
    IFS=';' read -r r g b <<< "$rgb"
    local max=$r
    (( g > max )) && max=$g
    (( b > max )) && max=$b
    (( max == 0 )) && echo "${target};${target};${target}" && return
    r=$(( r * target / max ))
    g=$(( g * target / max ))
    b=$(( b * target / max ))
    (( r > 255 )) && r=255
    (( g > 255 )) && g=255
    (( b > 255 )) && b=255
    echo "$r;$g;$b"
}

# --- Static palette computed once at source time ---

_fp_host="${HOSTNAME:-$(hostname 2>/dev/null || echo "localhost")}"
_fp_hostRGB=$(getRGBValue "$_fp_host")
_fp_lum=$(getLuminosity ${_fp_hostRGB//;/ })

_fp_hostFg="255;255;255"
(( _fp_lum > 128 )) && _fp_hostFg="0;0;0"

_fp_gitBg="20;30;130"
_fp_gitFg="255;220;50"
_fp_dirBg="22;22;22"
_fp_dirFg="210;210;210"

# Transition blocks with \001/\002 (SOH/STX) for correct cursor-width tracking
# in variables set by PROMPT_COMMAND.
#
#   _fp_gitBlock    : host→git arrow + git segment start
#   _fp_gitBlockEnd : git→dir arrow (when git segment is present)
#   _fp_noGitArrow  : host→dir arrow (when not in a git repo)
_fp_gitBlock=$(printf '\001\e[48;2;%s;38;2;%sm\002%s\001\e[48;2;%s;38;2;%sm\002' \
    "$_fp_gitBg" "$_fp_hostRGB" "$PL_R" "$_fp_gitBg" "$_fp_gitFg")
_fp_gitBlockEnd=$(printf '\001\e[48;2;%s;38;2;%sm\002%s' \
    "$_fp_dirBg" "$_fp_gitBg" "$PL_R")
_fp_noGitArrow=$(printf '\001\e[48;2;%s;38;2;%sm\002%s' \
    "$_fp_dirBg" "$_fp_hostRGB" "$PL_R")

# Static ANSI codes for the PS1 literal (wrapped with \[\] in PS1)
_fp_cHost="\e[48;2;${_fp_hostRGB};38;2;${_fp_hostFg}m"
_fp_cDir="\e[48;2;${_fp_dirBg};38;2;${_fp_dirFg}m"
_fp_cDirEnd="\e[0;38;2;${_fp_dirBg}m"   # reset → dir-bg fg for end-cap arrow
_fp_hostRGBBright=$(boostRGB "$_fp_hostRGB" 210)
_fp_gitBgBright=$(boostRGB "$_fp_gitBg" 185)
_fp_cTrim="\e[38;2;${_fp_hostRGBBright}m"
_fp_cAccent="\e[38;2;${_fp_gitBgBright}m"

[[ -n ${SUDO_USER:-} ]] && _fp_sudo=" ($SUDO_USER)" || _fp_sudo=""

# --- Dynamic indicator functions (called each prompt draw) ---

_fp_venv() {
    local name=""
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        name="$(basename "$VIRTUAL_ENV")"
    elif [[ -n "${CONDA_DEFAULT_ENV:-}" && "${CONDA_DEFAULT_ENV}" != "base" ]]; then
        name="$CONDA_DEFAULT_ENV"
    fi
    [[ -n "$name" ]] && printf '\001\e[38;2;80;200;100m\002(%.15s)\001\e[0m\002 ' "$name"
}

_fp_exit_code() {
    if [[ $1 -eq 0 ]]; then
        printf '\001\e[38;2;80;210;80m\002✓\001\e[0m\002 '
    else
        printf '\001\e[1;38;2;255;80;80m\002✗ %d\001\e[0m\002 ' "$1"
    fi
}

_fp_jobs() {
    local n
    n=$(jobs -p 2>/dev/null | wc -l)
    (( n > 0 )) && printf '\001\e[38;2;220;180;50m\002[%d&]\001\e[0m\002 ' "$n"
}

_fp_ssh() {
    [[ -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]] && \
        printf '\001\e[38;2;130;190;255m\002[ssh]\001\e[0m\002 '
}

# PS1_GIT_BLOCK adapts: full git segment with arrows when in a repo,
# single host→dir arrow when not.
# PS1_EXIT, PS1_SSH, PS1_VENV, PS1_JOBS update each draw.
# Append to PROMPT_COMMAND to preserve any existing hooks (conda, venv, direnv, etc.)
PROMPT_COMMAND='
    _fp_ec=$?
    PS1_CMD1=$(__git_ps1 " %s ")
    if [[ -n "$PS1_CMD1" ]]; then
        PS1_GIT_BLOCK="${_fp_gitBlock}${PS1_CMD1}${_fp_gitBlockEnd}"
    else
        PS1_GIT_BLOCK="$_fp_noGitArrow"
    fi
    [[ -n ${FP_LEVEL:-} && -n ${FP_FLAG:-} ]] && PS1_FLAG=$(getFlag "$FP_LEVEL" "$FP_FLAG") || PS1_FLAG=""
    PS1_EXIT=$(_fp_exit_code $_fp_ec)
    PS1_VENV=$(_fp_venv)
    PS1_JOBS=$(_fp_jobs)
    PS1_SSH=$(_fp_ssh)
'"${PROMPT_COMMAND:+
$PROMPT_COMMAND}"

# Layout:
#   [⚑ FLAG BANNER if set]
#   [user on host ][▶][git branch ][▶][ working/dir ][▶]
#   ✓/✗  [ssh] [venv] [jobs] date time ❯
PS1='${PS1_FLAG}''\n'"\[\e[0m${_fp_cHost}\] \u${_fp_sudo} on \H "'${PS1_GIT_BLOCK}'"\[${_fp_cDir}\] \w \[${_fp_cDirEnd}\]${PL_R}\[\e[0m\]"'\n''${PS1_EXIT}${PS1_SSH}${PS1_VENV}${PS1_JOBS}'"\[${_fp_cTrim}\]\d \T \[${_fp_cAccent}\]❯\[\e[0m\] "

export PS1
