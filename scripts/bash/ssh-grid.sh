#!/usr/bin/env bash
# ssh-grid.sh — select SSH hosts and output a Windows Terminal action JSON
#
# Presents a checklist of hosts from ~/.ssh/config, computes the most-square
# pane grid, and prints a JSON snippet ready to paste into the "actions" array
# in Windows Terminal's settings.json.
#
# Grid layout (cols = ceil(√N), rows = ceil(N/cols), left-to-right then down):
#   2 → [A|B]        3 → [A|B]      4 → [A|B]    5 → [A|B|C]
#                        [ C  ]          [C|D]        [ D | E ]
#
# Pane command: wsl.exe -- ssh <host>
#   This explicitly runs WSL's ssh so host aliases in ~/.ssh/config resolve.
#   Pass --distro NAME to target a specific WSL distribution.
#
# Requirements: whiptail, python3
#
# Usage: ssh-grid.sh [OPTIONS]
#   -c, --config PATH    SSH config file (default: ~/.ssh/config)
#   -d, --distro NAME    WSL distribution (default: wsl.exe default)
#   -h, --help           Show this help

set -euo pipefail

SSH_CONFIG="${HOME}/.ssh/config"
MAX_HOSTS=16
WSL_DISTRO=""

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/!d; s/^# \?//p }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config) SSH_CONFIG="$2"; shift 2 ;;
        -d|--distro) WSL_DISTRO="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for dep in whiptail python3; do
    command -v "$dep" &>/dev/null || { echo "Error: $dep is required" >&2; exit 1; }
done

# ── SSH config parser ─────────────────────────────────────────────────────────
# Emits "name|user" for each concrete host (first alias; skips wildcards).

parse_ssh_config() {
    local f="$1"
    local in_host=false names="" user="" line trimmed key val hval

    _flush() {
        if [[ "$in_host" == true && -n "$names" ]]; then echo "${names%% *}|${user}"; fi
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        if [[ "$trimmed" =~ ^[Mm]atch ]]; then
            _flush; in_host=false; names=""; user=""; continue
        fi

        if [[ "$trimmed" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
            _flush
            hval="${BASH_REMATCH[1]}"
            if [[ "$hval" == *[\*\?!]* ]]; then in_host=false; names=""; continue; fi
            names="$hval"; in_host=true; user=""; continue
        fi

        if [[ "$in_host" == true ]]; then
            read -r key val <<< "$trimmed"
            if [[ "${key,,}" == "user" ]]; then user="$val"; fi
        fi
    done < "$f"

    _flush
}

# ── Host selection UI ─────────────────────────────────────────────────────────

select_hosts() {
    local -a all_hosts=("$@")
    local count=${#all_hosts[@]}
    local list_h=$(( count < 18 ? count : 18 ))
    local box_h=$(( list_h + 8 ))
    local -a items=()
    for h in "${all_hosts[@]}"; do items+=("$h" "" "OFF"); done

    local result
    result=$(
        whiptail --title "SSH Grid" \
            --checklist "Select hosts  (SPACE = toggle, ENTER = confirm, first ${MAX_HOSTS} used):" \
            "$box_h" 64 "$list_h" \
            "${items[@]}" 3>&1 1>&2 2>&3
    ) || return 1

    echo "$result" | tr -d '"'
}

# ── Grid math ─────────────────────────────────────────────────────────────────

calc_grid() {
    python3 - "$1" <<'PY'
import sys, math
n = int(sys.argv[1])
cols = math.ceil(math.sqrt(n))
rows = math.ceil(n / cols)
print(cols, rows)
PY
}

# ── wt commandline builder ────────────────────────────────────────────────────
# Outputs the argument string for wt.exe (the value of "commandline" in the
# WT action JSON). Subcommands are separated by " ; ".

build_commandline() {
    local -a hosts=("$@")
    local n=${#hosts[@]}

    read -r cols rows < <(calc_grid "$n")

    fdiv() { awk "BEGIN {s=sprintf(\"%.4f\",$1/$2); sub(/\\.?0+$/,\"\",s); print s}"; }

    local wsl_prefix="wsl.exe"
    [[ -n "$WSL_DISTRO" ]] && wsl_prefix="wsl.exe -d ${WSL_DISTRO}"

    pane_cmd() {
        local u="${HOST_USER[$1]:-}"
        echo "-- ${wsl_prefix} -- ssh ${u:+${u}@}${1}"
    }

    local -a parts=()
    local next_pane=1
    local -a row_panes=()

    # Phase 1: new-tab for hosts[0], then one -H split per row.
    # Each -H split naturally applies to the previously created row pane (focus follows).
    # No --target needed here.
    parts+=("new-tab $(pane_cmd "${hosts[0]}")")
    row_panes+=(0)

    for (( i=1; i<rows; i++ )); do
        local hi=$(( i * cols ))
        [[ $hi -ge $n ]] && break
        local size; size=$(fdiv $(( rows - i )) $(( rows - i + 1 )))
        parts+=("split-pane -H --size ${size} $(pane_cmd "${hosts[$hi]}")")
        row_panes+=("$next_pane")
        (( next_pane++ ))
    done

    # Phase 2: column splits within each row.
    # Navigate to the row's initial pane, then alternate split/focus-pane so every
    # V-split is explicitly targeted — WT's focus can drift in a newWindow action.
    for (( r=0; r<rows; r++ )); do
        local row_start=$(( r * cols ))
        local row_end=$(( row_start + cols ))
        [[ $row_end -gt $n ]] && row_end=$n
        local n_r=$(( row_end - row_start ))
        [[ $n_r -lt 2 ]] && continue

        [[ $rows -gt 1 ]] && parts+=("focus-pane -t ${row_panes[$r]}")

        for (( c=1; c<n_r; c++ )); do
            local size; size=$(fdiv $(( cols - c )) $(( cols - c + 1 )))
            parts+=("split-pane -V --size ${size} $(pane_cmd "${hosts[$(( row_start + c ))]}")")
            local created=$next_pane
            (( next_pane++ ))
            # Re-focus the pane we just created so the next V-split targets it, not
            # whatever WT considers active after the split.
            (( c < n_r - 1 )) && parts+=("focus-pane -t ${created}")
        done
    done

    local result="${parts[0]}"
    for (( j=1; j<${#parts[@]}; j++ )); do result+=" ; ${parts[$j]}"; done
    echo "$result"
}

# ── Main ──────────────────────────────────────────────────────────────────────

[[ -f "$SSH_CONFIG" ]] || { echo "Error: SSH config not found: $SSH_CONFIG" >&2; exit 1; }

declare -A HOST_USER=()
all_hosts=()

while IFS='|' read -r hname huser; do
    [[ -z "$hname" ]] && continue
    all_hosts+=("$hname")
    HOST_USER["$hname"]="$huser"
done < <(parse_ssh_config "$SSH_CONFIG")

[[ ${#all_hosts[@]} -eq 0 ]] && { echo "No hosts found in $SSH_CONFIG." >&2; exit 1; }

selected_str=$(select_hosts "${all_hosts[@]}") || { echo "Cancelled." >&2; exit 0; }
[[ -z "$selected_str" ]] && { echo "No hosts selected." >&2; exit 0; }

read -ra selected <<< "$selected_str"
[[ ${#selected[@]} -gt $MAX_HOSTS ]] && selected=("${selected[@]:0:$MAX_HOSTS}")
n=${#selected[@]}

read -r cols rows < <(calc_grid "$n")
echo "Grid: ${cols}×${rows} (${n} hosts)" >&2

build_commandline "${selected[@]}"
