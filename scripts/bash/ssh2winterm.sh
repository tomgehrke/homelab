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
#
# Windows Terminal uses deterministic UUIDv5 for fragment profiles:
#   1. App namespace  = UUIDv5(WT_fragment_namespace, app_name as UTF-16LE)
#   2. Profile GUID   = UUIDv5(app_namespace, profile_name as UTF-16LE)
#
# This matches the algorithm documented by Microsoft. The key detail is that
# the "name" input must be encoded as UTF-16LE before hashing — plain UTF-8
# will produce the wrong GUID, and your profile customizations in settings.json
# will get orphaned when you regenerate.

generate_guid() {
    local app_name="$1"
    local profile_name="$2"

    python3 - "$app_name" "$profile_name" << 'PYEOF'
import uuid, hashlib, sys

def uuid5_utf16le(namespace, name_str):
    """UUIDv5 using UTF-16LE encoding for the name, matching Windows Terminal's algorithm."""
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
#
# Handles:
#   - Host entries (single and multi-host lines)
#   - Skipping wildcards (*, ?, !)
#   - Skipping Match blocks
#   - Extracting HostName, User, Port, ProxyJump for tooltip/tab title

emit_hosts() {
    # Emits one line per host name in the block, fields separated by "|"
    # We use "|" instead of tab because bash's `read` with IFS=$'\t'
    # collapses consecutive tabs — meaning empty fields get swallowed
    # and subsequent values shift left into the wrong variables.
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
        # Strip leading and trailing whitespace without a subshell
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

        # Skip comments and blank lines
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        # Match block — flush current and ignore
        if [[ "$trimmed" =~ ^[Mm]atch[[:space:]] ]]; then
            if [[ "$in_host" == true ]]; then
                emit_hosts "$host_names" "$hostname" "$user" "$port" "$proxyjump"
            fi
            in_host=false
            host_names=""
            hostname="" user="" port="" proxyjump=""
            continue
        fi

        # Host line
        if [[ "$trimmed" =~ ^[Hh]ost[[:space:]]+(.+)$ ]]; then
            # Flush previous host block
            if [[ "$in_host" == true ]]; then
                emit_hosts "$host_names" "$hostname" "$user" "$port" "$proxyjump"
            fi

            host_value="${BASH_REMATCH[1]}"

            # Skip wildcards/patterns
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

        # Directives under a Host block
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

    # Flush last block
    if [[ "$in_host" == true ]]; then
        emit_hosts "$host_names" "$hostname" "$user" "$port" "$proxyjump"
    fi
}

# Build JSON ────────────────────────────────────────────────────────────────

build_profiles_json() {
    local hosts_tsv="$1"
    local profiles_json="[]"
    local name hostname user port proxyjump
    local display_name group rest guid tab_title details profile_obj

    while IFS='|' read -r name hostname user port proxyjump; do
        [[ -z "$name" ]] && continue

        # Display name and optional folder group
        display_name="$name"
        group="$FRAGMENT_NAME"
        if [[ "$GROUP_BY_PREFIX" == true && "$name" == *-* ]]; then
            group="${FRAGMENT_NAME}/${name%%-*}"
        fi

        # Generate deterministic GUID
        guid="$(generate_guid "$FRAGMENT_NAME" "$name")"

        # Build SSH command, incorporating user if specified in config
        local ssh_cmd="ssh $name"
        [[ -n "$user" ]] && ssh_cmd="ssh ${user}@${name}"

        # Build tab title with connection details
        tab_title=""
        details=""
        [[ -n "$hostname" ]]  && details="Host: $hostname"
        [[ -n "$user" ]]      && details="${details:+$details, }User: $user"
        [[ -n "$port" ]]      && details="${details:+$details, }Port: $port"
        [[ -n "$proxyjump" ]] && details="${details:+$details, }Via: $proxyjump"

        if [[ -n "$details" ]]; then
            tab_title="${name} (${details})"
        fi

        # Build the profile object with jq
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

        profiles_json="$(echo "$profiles_json" | jq --argjson p "$profile_obj" '. + [$p]')"

    done <<< "$hosts_tsv"

    # group is retained here for update_new_tab_menu to build sub-folder structure
    # but is stripped from the fragment file itself before writing (see main).
    echo "$profiles_json" | jq '{profiles: sort_by(.name)}'
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

# Writes (or replaces) our folder entry in settings.json's newTabMenu, using
# matchProfiles by source so WT resolves profiles by fragment origin rather than
# by GUID. Preserves any other newTabMenu entries the user has configured.
update_new_tab_menu() {
    local profiles_json="$1"
    local settings_file
    settings_file="$(resolve_settings_json)"

    if [[ -z "$settings_file" ]]; then
        echo "Warning: Could not find settings.json; add newTabMenu entry manually." >&2
        return
    fi

    # Build the folder entry using matchProfiles by source (the fragment folder name).
    # This lets WT resolve profiles by their fragment origin rather than by explicit
    # GUIDs, which may differ from what WT internally assigns to fragment profiles.
    # With --group-by-prefix, sub-group names are derived from the group field.
    # Simple flat folder using matchProfiles — always works since WT resolves
    # fragment profiles by their source (the fragment folder name).
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
        # Direct profiles (no sub-group) listed individually; prefixed profiles
        # grouped into sub-folders. No matchProfiles catch-all — that would
        # duplicate every profile above the sub-folders.
        folder_entry="$(printf '%s' "$profiles_json" | jq \
            --arg name "$FRAGMENT_NAME" \
            --arg icon "$ICON_DEFAULT" \
            '
            (.profiles | map(select(.group | test("/") | not))) as $direct |
            (.profiles | map(select(.group | test("/"))) | group_by(.group | split("/")[1])
            ) as $subgroups |
            {
                "type": "folder",
                "name": $name,
                "icon": $icon,
                "entries": (
                    ($direct | map({"type": "profile", "profile": .name})) +
                    ($subgroups | map({
                        "type": "folder",
                        "name": (.[0].group | split("/")[1]),
                        "entries": [.[] | {"type": "profile", "profile": .name}]
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

    echo "Settings.json path: ${settings_file}" >&2
    echo "newTabMenu folder entry to be written:" >&2
    echo "$folder_entry" | jq '.' >&2

    # settings.json is JSONC — strip // and /* */ comments before jq can parse it.
    local clean_json
    clean_json="$(python3 - "$settings_file" << 'PYEOF'
import sys, re
txt = open(sys.argv[1], encoding='utf-8').read()
# Remove // comments but leave // inside quoted strings untouched
txt = re.sub(r'("(?:[^"\\]|\\.)*")|//[^\n]*', lambda m: m.group(1) or '', txt)
# Remove /* */ block comments
txt = re.sub(r'/\*.*?\*/', '', txt, flags=re.DOTALL)
print(txt)
PYEOF
    )"

    if [[ -z "$clean_json" ]]; then
        echo "Warning: Could not parse settings.json; add newTabMenu entry manually." >&2
        return
    fi

    local tmpfile
    tmpfile="$(mktemp)"
    local jq_err
    if printf '%s\n' "$clean_json" | jq --argjson folder "$folder_entry" --arg fname "$FRAGMENT_NAME" '
        (.newTabMenu // [{"type": "remainingProfiles"}]) as $existing |
        (if ($existing | any(.[]; .type == "remainingProfiles"))
         then $existing
         else [{"type": "remainingProfiles"}] + $existing end) as $with_remaining |
        .newTabMenu = (
            ($with_remaining | map(select(.type != "folder" or .name != $fname))) +
            [$folder]
        )
    ' > "$tmpfile" 2>/tmp/ssh2winterm_jq_err && mv "$tmpfile" "$settings_file"; then
        echo "Updated newTabMenu (${FRAGMENT_NAME} folder) in: ${settings_file}" >&2
    else
        jq_err="$(cat /tmp/ssh2winterm_jq_err 2>/dev/null)"
        rm -f "$tmpfile" /tmp/ssh2winterm_jq_err
        echo "Warning: Failed to update newTabMenu in settings.json." >&2
        [[ -n "$jq_err" ]] && echo "  jq error: ${jq_err}" >&2
        echo "  Add this entry manually to your newTabMenu in settings.json:" >&2
        echo "$folder_entry" | jq '.' >&2
    fi
}

# Fragment profiles can be shadowed by stale overrides in settings.json that
# have hidden:true — those entries take precedence and the profile vanishes
# from the UI (but still appears in the "Copy a profile" dialog). This removes
# the hidden flag from any settings.json override that matches one of our GUIDs.
unhide_fragment_profiles() {
    local guids_json="$1"
    local settings_file
    settings_file="$(resolve_settings_json)"
    [[ -z "$settings_file" ]] && return

    local hidden_count
    hidden_count="$(jq --argjson guids "$guids_json" '
        [(.profiles.list // [])[] |
         select(.hidden == true and (.guid as $g | $guids | index($g)) != null)] | length
    ' "$settings_file")"

    [[ "$hidden_count" -eq 0 ]] && return

    local tmpfile
    tmpfile="$(mktemp)"
    if jq --argjson guids "$guids_json" '
        if .profiles.list? then
            .profiles.list |= map(
                if (.hidden == true and (.guid as $g | $guids | index($g)) != null)
                then del(.hidden)
                else . end
            )
        else . end
    ' "$settings_file" > "$tmpfile" && mv "$tmpfile" "$settings_file"; then
        echo "Unhid ${hidden_count} fragment profile(s) in: ${settings_file}" >&2
    else
        rm -f "$tmpfile"
        echo "Warning: Failed to unhide profiles in settings.json." >&2
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
    # Strip group before display: it's WT metadata used only for newTabMenu building
    echo "$json" | jq '{profiles: [.profiles[] | del(.group)]}'
else
    fragment_dir="$(resolve_fragment_dir)"

    mkdir -p "$fragment_dir"
    fragment_path="${fragment_dir}/profiles.json"

    # Strip group from the fragment file. The group property tells WT to remove
    # profiles from the flat default view, so keeping it without a matching
    # newTabMenu folder entry causes profiles to vanish entirely.
    echo "$json" | jq '{profiles: [.profiles[] | del(.group)]}' > "$fragment_path"
    echo "Fragment written to: ${fragment_path}" >&2

    guids_json="$(echo "$json" | jq '[.profiles[].guid]')"
    unhide_fragment_profiles "$guids_json"
    update_new_tab_menu "$json"

    echo "Restart Windows Terminal to pick up the new profiles." >&2
fi

echo "" >&2
echo "Generated profiles:" >&2
echo "$hosts_tsv" | while IFS='|' read -r name hostname user port proxyjump; do
    display="$name"
    if [[ "$GROUP_BY_PREFIX" == true && "$name" == *-* ]]; then
        display="${name%%-*}/${name#*-}"
    fi
    ssh_target="$name"
    [[ -n "$user" ]] && ssh_target="${user}@${name}"
    echo "  ${display}  ->  ssh ${ssh_target}" >&2
done
