#!/usr/bin/env bash
#
# ssh2winterm.sh
#
# Parses ~/.ssh/config and generates a Windows Terminal JSON fragment file.
#
# The fragment should go here:
#   %LOCALAPPDATA%/Microsoft/Windows Terminal/Fragments/<fragment-name>/profiles.json
#
# When run from WSL, the script resolves %LOCALAPPDATA% via wslpath.
# When run from Git Bash / MSYS2, it uses the LOCALAPPDATA env var directly.
#
# Usage:
#   ./ssh2winterm.sh [OPTIONS]
#
# Options:
#   -c, --config PATH        SSH config path (default: ~/.ssh/config)
#   -n, --name NAME          Fragment folder name (default: SSHProfiles)
#   -i, --icon ICON          Default icon emoji or path (default: 🖥️)
#   -g, --group-by-prefix    Group hosts into folders by first segment before '-'
#   -e, --exclude PATTERN    Regex pattern for host names to exclude
#   -d, --dry-run            Print JSON to stdout instead of writing file
#   -h, --help               Show this help
#
# Requirements:
#   - jq  (for JSON generation)
#   - python3  (for deterministic GUID generation)
#   - wslpath (auto-detected in WSL) or LOCALAPPDATA env var

set -euo pipefail

# Defaults ──────────────────────────────────────────────────────────────────

SSH_CONFIG="${HOME}/.ssh/config"
FRAGMENT_NAME="SSHProfiles"
ICON_DEFAULT="🖥️"
GROUP_BY_PREFIX=false
EXCLUDE_PATTERN=""
DRY_RUN=false

# Usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat << 'EOF'
Usage:
  ./ssh2winterm.sh [OPTIONS]

Options:
  -c, --config PATH        SSH config path (default: ~/.ssh/config)
  -n, --name NAME          Fragment folder name (default: SSHProfiles)
  -i, --icon ICON          Default icon emoji or path (default: 🖥️)
  -g, --group-by-prefix    Group hosts into sub-folders by first segment before '-'
  -e, --exclude PATTERN    Regex pattern for host names to exclude
  -d, --dry-run            Print JSON to stdout instead of writing file
  -h, --help               Show this help
EOF
    exit 0
}

# Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)          SSH_CONFIG="$2"; shift 2 ;;
        -n|--name)            FRAGMENT_NAME="$2"; shift 2 ;;
        -i|--icon)            ICON_DEFAULT="$2"; shift 2 ;;
        -g|--group-by-prefix) GROUP_BY_PREFIX=true; shift ;;
        -e|--exclude)         EXCLUDE_PATTERN="$2"; shift 2 ;;
        -d|--dry-run)         DRY_RUN=true; shift ;;
        -h|--help)            usage ;;
        *)                    echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Dependency checks ────────────────────────────────────────────────────────

check_dependencies() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed." >&2
        echo "  Ubuntu/Debian: sudo apt install jq" >&2
        echo "  macOS:         brew install jq" >&2
        echo "  MSYS2:         pacman -S jq" >&2
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        echo "Error: python3 is required for deterministic GUID generation." >&2
        exit 1
    fi
}

# GUID generation ──────────────────────────────────────────────────────────

generate_guid() {
    local app_name="$1"
    local profile_name="$2"

    python3 - "$app_name" "$profile_name" << 'PYEOF'
import uuid, hashlib, sys

def uuid5_utf16le(namespace, name_str):
    name_bytes = name_str.encode('utf-16-le')
    digest = hashlib.sha1(namespace.bytes + name_bytes).digest()
    return uuid.UUID(bytes=digest[:16], version=5)

terminal_ns = uuid.UUID('{f65ddb7e-706b-4499-8a50-40313caf510a}')
app_ns = uuid5_utf16le(terminal_ns, sys.argv[1])
profile_guid = uuid5_utf16le(app_ns, sys.argv[2])
print('{' + str(profile_guid) + '}')
PYEOF
}

# Parse SSH config ──────────────────────────────────────────────────────────

emit_hosts() {
    local names_str="$1" hostname="$2" user="$3" port="$4" proxyjump="$5"
    local name="${names_str%% *}"

    if [[ -n "$EXCLUDE_PATTERN" && "$name" =~ $EXCLUDE_PATTERN ]]; then
        return
    fi
    echo "${name}|${hostname}|${user}|${port}|${proxyjump}"
}

parse_ssh_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        echo "Error: SSH config not found at: $config_file" >&2
        exit 1
    fi

    local in_host=false
    local host_names=""
    local hostname="" user="" port="" proxyjump=""
    local trimmed key val host_value

    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        if [[ "$trimmed" =~ ^[Mm]atch[[:space:]] ]]; then
            if [[ "$in_host" == true ]]; then
                emit_hosts "$host_names" "$hostname" "$user" "$port" "$proxyjump"
            fi
            in_host=false
            host_names=""
            hostname="" user="" port="" proxyjump=""
            continue
        fi

        if [[ "$trimmed" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
            if [[ "$in_host" == true ]]; then
                emit_hosts "$host_names" "$hostname" "$user" "$port" "$proxyjump"
            fi

            host_value="${BASH_REMATCH[1]}"

            if [[ "$host_value" == *[\*\?!]* ]]; then
                in_host=false
                host_names=""
                continue
            fi

            host_names="$host_value"
            in_host=true
            hostname="" user="" port="" proxyjump=""
            continue
        fi

        if [[ "$in_host" == true ]]; then
            read -r key val <<< "$trimmed"
            key="${key,,}"

            case "$key" in
                hostname)     hostname="$val" ;;
                user)         user="$val" ;;
                port)         port="$val" ;;
                proxyjump)    proxyjump="$val" ;;
            esac
        fi
    done < "$config_file"

    if [[ "$in_host" == true ]]; then
        emit_hosts "$host_names" "$hostname" "$user" "$port" "$proxyjump"
    fi
}

# Build JSON ────────────────────────────────────────────────────────────────

build_profiles_json() {
    local hosts_tsv="$1"
    local profiles_json="[]"
    local name hostname user port proxyjump
    local display_name group guid tab_title details profile_obj k v ssh_cmd

    declare -A _final_dn=()
    while IFS='|' read -r name _ _ _ _; do
        [[ -z "$name" ]] && continue
        if [[ "$GROUP_BY_PREFIX" == true && "$name" == *-* ]]; then
            _final_dn["$name"]="${name#*-}"
        else
            _final_dn["$name"]="$name"
        fi
    done <<< "$hosts_tsv"

    local _changed=true
    declare -A _freq=()
    while [[ "$_changed" == true ]]; do
        _changed=false
        unset _freq; declare -A _freq
        for k in "${!_final_dn[@]}"; do
            v="${_final_dn[$k]}"
            _freq["$v"]=$(( ${_freq["$v"]:-0} + 1 ))
        done
        for k in "${!_final_dn[@]}"; do
            v="${_final_dn[$k]}"
            if [[ "${_freq[$v]:-0}" -gt 1 && "$v" != "$k" ]]; then
                _final_dn["$k"]="$k"
                _changed=true
            fi
        done
    done

    local _dup_found=false
    for k in "${!_final_dn[@]}"; do
        v="${_final_dn[$k]}"
        if [[ "${_freq[$v]:-0}" -gt 1 ]]; then
            if [[ "$_dup_found" == false ]]; then
                echo "Error: duplicate display names remain after collision resolution:" >&2
                _dup_found=true
            fi
            echo "  display='$v'  alias='$k'" >&2
        fi
    done
    if [[ "$_dup_found" == true ]]; then
        echo "  → Two SSH aliases resolve to the same profile name → same GUID → WT error." >&2
        echo "  → Rename one of the conflicting aliases in your SSH config." >&2
        return 1
    fi

    while IFS='|' read -r name hostname user port proxyjump; do
        [[ -z "$name" ]] && continue

        display_name="${_final_dn[$name]}"
        group="$FRAGMENT_NAME"
        if [[ "$GROUP_BY_PREFIX" == true && "$name" == *-* ]]; then
            group="${FRAGMENT_NAME}/${name%%-*}"
        fi

        guid="$(generate_guid "$FRAGMENT_NAME" "$display_name")"

        ssh_cmd="ssh $name"
        [[ -n "$user" ]] && ssh_cmd="ssh ${user}@${name}"

        tab_title=""
        details=""
        [[ -n "$hostname" ]]  && details="Host: $hostname"
        [[ -n "$user" ]]      && details="${details:+$details, }User: $user"
        [[ -n "$port" ]]      && details="${details:+$details, }Port: $port"
        [[ -n "$proxyjump" ]] && details="${details:+$details, }Via: $proxyjump"

        if [[ -n "$details" ]]; then
            tab_title="${name} (${details})"
        fi

        profile_obj="$(jq -n \
            --arg name "$display_name" \
            --arg cmd "$ssh_cmd" \
            --arg guid "$guid" \
            --arg icon "$ICON_DEFAULT" \
            --arg tabTitle "$tab_title" \
            --arg group "$group" \
            '{
                name: $name,
                commandline: $cmd,
                guid: $guid,
                icon: $icon
            }
            | if $tabTitle != "" then . + {tabTitle: $tabTitle} else . end
            | if $group != "" then . + {group: $group} else . end
            '
        )"

        profiles_json="$(printf '%s' "$profiles_json" | jq --argjson p "$profile_obj" '. + [$p]')"

    done <<< "$hosts_tsv"

    printf '%s' "$profiles_json" | jq '{profiles: sort_by(.name)}'
}

# Resolve output path ──────────────────────────────────────────────────────

resolve_localappdata() {
    if command -v wslpath &>/dev/null; then
        local win_localappdata
        win_localappdata="$(cmd.exe /C "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')"
        wslpath "$win_localappdata"
    elif [[ -n "${LOCALAPPDATA:-}" ]]; then
        echo "$LOCALAPPDATA"
    else
        echo ""
    fi
}

resolve_fragment_dir() {
    local base
    base="$(resolve_localappdata)"
    if [[ -z "$base" ]]; then
        echo "Error: Cannot determine Windows LOCALAPPDATA path." >&2
        echo "  Set LOCALAPPDATA or run from WSL / Git Bash." >&2
        exit 1
    fi
    echo "${base}/Microsoft/Windows Terminal/Fragments/${FRAGMENT_NAME}"
}

resolve_settings_json() {
    local base
    base="$(resolve_localappdata)"
    [[ -z "$base" ]] && echo "" && return
    local candidates=(
        "${base}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
        "${base}/Microsoft/Windows Terminal/settings.json"
        "${base}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
    )
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && echo "$f" && return
    done
    echo ""
}

# Strip JSONC comments from a file and print clean JSON to stdout.
strip_jsonc() {
    python3 - "$1" << 'PYEOF'
import sys, re
try:
    with open(sys.argv[1], encoding='utf-8-sig') as f:
        txt = f.read()
    # Remove // line comments but leave // inside quoted strings untouched
    txt = re.sub(r'("(?:[^"\\]|\\.)*")|//[^\n]*', lambda m: m.group(1) or '', txt)
    # Remove /* */ block comments
    txt = re.sub(r'/\*.*?\*/', '', txt, flags=re.DOTALL)
    # Strip trailing commas that crash jq parsing
    txt = re.sub(r',\s*([\]}])', r'\1', txt)
    
    # Write directly to standard output buffer to prevent Windows CP1252 
    # encoding crashes when encountering emojis like 🖥️
    sys.stdout.buffer.write(txt.encode('utf-8'))
except Exception as e:
    sys.stderr.write(f"Python JSON processing error: {e}\n")
PYEOF
}

# Writes (or replaces) our folder entry in settings.json's newTabMenu.
update_new_tab_menu() {
    local profiles_json="$1"
    local settings_file
    settings_file="$(resolve_settings_json)"

    if [[ -z "$settings_file" ]]; then
        echo "Warning: Could not find settings.json; add newTabMenu entry manually." >&2
        return
    fi

    local flat_folder_entry
    flat_folder_entry="$(jq -n \
        --arg name "$FRAGMENT_NAME" \
        --arg icon "$ICON_DEFAULT" \
        '{
            "type": "folder",
            "name": $name,
            "icon": $icon,
            "entries": [{"type": "matchProfiles", "source": $name}]
        }'
    )"

    local folder_entry
    if [[ "$GROUP_BY_PREFIX" == false ]]; then
        folder_entry="$flat_folder_entry"
    else
        folder_entry="$(printf '%s' "$profiles_json" | jq \
            --arg name "$FRAGMENT_NAME" \
            --arg icon "$ICON_DEFAULT" \
            '
            (.profiles | map(select(.group | contains("/") | not))) as $direct |
            (.profiles | map(select(.group | contains("/")))) | group_by(.group | split("/")[1]) as $subgroups |
            {
                "type": "folder",
                "name": $name,
                "icon": $icon,
                "entries": (
                    ($direct | map({"type": "profile", "profile": .guid})) +
                    ($subgroups | map({
                        "type": "folder",
                        "name": (.[0].group | split("/")[1]),
                        "entries": [.[] | {"type": "profile", "profile": .guid}]
                    }))
                )
            }
            ' 2>/dev/null
        )"
        if [[ -z "$folder_entry" ]]; then
            echo "Warning: Could not build grouped newTabMenu entry; falling back to flat folder." >&2
            folder_entry="$flat_folder_entry"
        fi
    fi

    local clean_json
    clean_json="$(strip_jsonc "$settings_file")"

    if [[ -z "$clean_json" ]]; then
        echo "Warning: Could not parse settings.json; add newTabMenu entry manually." >&2
        return
    fi

    local tmpfile
    tmpfile="$(mktemp)"
    
    # Injects the folder logic in a way compatible with both new and old versions of jq.
    if printf '%s\n' "$clean_json" | jq --argjson folder "$folder_entry" --arg fname "$FRAGMENT_NAME" '
        (.newTabMenu // [{"type": "remainingProfiles"}]) as $existing |
        (if ($existing | map(select(.type == "remainingProfiles")) | length > 0)
         then $existing
         else [{"type": "remainingProfiles"}] + $existing end) as $with_remaining |
        .newTabMenu = (
            ($with_remaining | map(select(.type != "folder" or .name != $fname))) +
            [$folder]
        )
    ' > "$tmpfile" 2>/tmp/ssh2winterm_jq_err && mv "$tmpfile" "$settings_file"; then
        echo "Updated newTabMenu (${FRAGMENT_NAME} folder) in: ${settings_file}" >&2
    else
        local jq_err
        jq_err="$(cat /tmp/ssh2winterm_jq_err 2>/dev/null || true)"
        rm -f "$tmpfile" /tmp/ssh2winterm_jq_err
        echo "Warning: Failed to update newTabMenu in settings.json." >&2
        [[ -n "$jq_err" ]] && echo "  jq error: ${jq_err}" >&2
        echo "  Add this entry manually to your newTabMenu in settings.json:" >&2
        printf '%s' "$folder_entry" | jq '.' >&2
    fi
}

unhide_fragment_profiles() {
    local guids_json="$1"
    local settings_file
    settings_file="$(resolve_settings_json)"
    [[ -z "$settings_file" ]] && return

    local clean_json
    clean_json="$(strip_jsonc "$settings_file")"
    [[ -z "$clean_json" ]] && return

    local hidden_count
    hidden_count="$(printf '%s' "$clean_json" | jq --argjson guids "$guids_json" '
        [(.profiles.list // [])[] |
         select(.hidden == true and (.guid as $g | $guids | index($g)) != null)] | length
    ')"

    [[ "$hidden_count" -eq 0 ]] && return

    local tmpfile
    tmpfile="$(mktemp)"
    if printf '%s\n' "$clean_json" | jq --argjson guids "$guids_json" '
        if .profiles.list? then
            .profiles.list |= map(
                if (.hidden == true and (.guid as $g | $guids | index($g)) != null)
                then del(.hidden)
                else . end
            )
        else . end
    ' > "$tmpfile" && mv "$tmpfile" "$settings_file"; then
        echo "Unhid ${hidden_count} fragment profile(s) in: ${settings_file}" >&2
    else
        rm -f "$tmpfile"
        echo "Warning: Failed to unhide profiles in settings.json." >&2
    fi
}

cleanup_stale_profiles() {
    local old_guids_json="$1"
    local new_guids_json="$2"
    local settings_file
    settings_file="$(resolve_settings_json)"
    [[ -z "$settings_file" ]] && return

    local clean_json
    clean_json="$(strip_jsonc "$settings_file")"
    [[ -z "$clean_json" ]] && return

    local stale_count
    stale_count="$(printf '%s' "$clean_json" | jq \
        --argjson old "$old_guids_json" \
        --argjson new "$new_guids_json" \
        --arg source "$FRAGMENT_NAME" \
        '
        ($old | map(select(. as $g | ($new | index($g)) == null))) as $from_old |
        ([(.profiles.list // [])[] |
          select(.source == $source and (.guid as $g | ($new | index($g)) == null)) |
          .guid]) as $from_settings |
        ($from_old + $from_settings | unique) | length
        '
    )"

    [[ "$stale_count" -eq 0 ]] && return

    local tmpfile
    tmpfile="$(mktemp)"
    if printf '%s\n' "$clean_json" | jq \
        --argjson old "$old_guids_json" \
        --argjson new "$new_guids_json" \
        --arg source "$FRAGMENT_NAME" \
        '
        ($old | map(select(. as $g | ($new | index($g)) == null))) as $from_old |
        ([(.profiles.list // [])[] |
          select(.source == $source and (.guid as $g | ($new | index($g)) == null)) |
          .guid]) as $from_settings |
        ($from_old + $from_settings | unique) as $stale |
        if .profiles.list? then
            .profiles.list |= map(select(.guid as $g | ($stale | index($g)) == null))
        else . end
        ' > "$tmpfile" && mv "$tmpfile" "$settings_file"; then
        echo "Removed ${stale_count} stale profile override(s) from: ${settings_file}" >&2
    else
        rm -f "$tmpfile"
        echo "Warning: Failed to clean up stale profiles from settings.json." >&2
    fi
}

# Main ──────────────────────────────────────────────────────────────────────

check_dependencies

echo "Reading SSH config from: ${SSH_CONFIG}" >&2

hosts_tsv="$(parse_ssh_config "$SSH_CONFIG")"

if [[ -z "$hosts_tsv" ]]; then
    echo "No concrete SSH hosts found in config." >&2
    exit 0
fi

host_count="$(echo "$hosts_tsv" | wc -l)"
echo "Found ${host_count} SSH host(s)" >&2

json="$(build_profiles_json "$hosts_tsv")"

if [[ "$DRY_RUN" == true ]]; then
    echo "" >&2
    echo "--- Fragment JSON (dry run) ---" >&2
    printf '%s' "$json" | jq '{profiles: [.profiles[] | del(.group)]}'
else
    fragment_dir="$(resolve_fragment_dir)"
    mkdir -p "$fragment_dir"
    fragment_path="${fragment_dir}/profiles.json"

    fragments_parent="${fragment_dir%/*}"
    if [[ -d "$fragments_parent" ]]; then
        while IFS= read -r -d '' stale_dir; do
            [[ "$(basename "$stale_dir")" == "$FRAGMENT_NAME" ]] && continue
            echo "Warning: stale fragment directory found: ${stale_dir}" >&2
            echo "  Windows Terminal will keep showing its profiles until you delete it." >&2
        done < <(find "$fragments_parent" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    old_guids_json="[]"
    if [[ -f "$fragment_path" ]]; then
        old_guids_json="$(jq '[.profiles[].guid]' "$fragment_path" 2>/dev/null || echo "[]")"
    fi

    printf '%s' "$json" | jq '{profiles: [.profiles[] | del(.group)]}' > "$fragment_path"
    echo "Fragment written to: ${fragment_path}" >&2

    new_guids_json="$(printf '%s' "$json" | jq '[.profiles[].guid]')"
    cleanup_stale_profiles "$old_guids_json" "$new_guids_json"
    unhide_fragment_profiles "$new_guids_json"
    update_new_tab_menu "$json"

    echo "Restart Windows Terminal to pick up the new profiles." >&2
fi

echo "" >&2
echo "Generated profiles:" >&2
printf '%s' "$json" | jq -r '
    .profiles[] |
    (if (.group? // "") | contains("/") then
        ((.group | split("/")[1:] | join("/")) + "/" + .name)
    else
        .name
    end) + "  ->  " + .commandline
' | while IFS= read -r line; do
    echo "  $line" >&2
done