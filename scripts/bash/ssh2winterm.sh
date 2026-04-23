#!/usr/bin/env bash
# ssh2winterm.sh — generate Windows Terminal profiles from ~/.ssh/config
#
# SSH host aliases with a dash-prefix (e.g. prd-server01) are grouped into
# sub-folders named after the prefix (prd) inside a top-level SSHProfiles
# folder in the Windows Terminal new-tab menu. Un-prefixed hosts appear at
# the top of that folder.
#
# Requirements: jq, python3
# WSL:      wslpath must be available (it is by default)
# Git Bash: LOCALAPPDATA env var must be set (it is by default)
#
# Usage: ./ssh2winterm.sh [OPTIONS]
#   -c, --config PATH        SSH config file (default: ~/.ssh/config)
#   -n, --name   NAME        Fragment and folder name (default: SSHProfiles)
#   -l, --localappdata PATH  Windows LOCALAPPDATA as a WSL path
#                            (auto-detected; use this if auto-detect fails)
#   -d, --dry-run            Print fragment JSON to stdout; skip all file writes
#   -h, --help               Show this help

set -euo pipefail

SSH_CONFIG="${HOME}/.ssh/config"
FRAGMENT_NAME="SSHProfiles"
LOCALAPPDATA_OVERRIDE=""
DRY_RUN=false

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/!d; s/^# \?//p }' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)       SSH_CONFIG="$2"; shift 2 ;;
        -n|--name)         FRAGMENT_NAME="$2"; shift 2 ;;
        -l|--localappdata) LOCALAPPDATA_OVERRIDE="$2"; shift 2 ;;
        -d|--dry-run)      DRY_RUN=true; shift ;;
        -h|--help)         usage ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for dep in jq python3; do
    command -v "$dep" &>/dev/null || { echo "Error: $dep is required" >&2; exit 1; }
done

# ── SSH config parser ────────────────────────────────────────────────────────
# Emits pipe-delimited records: name|user
# Skips wildcard hosts, Match blocks, and blank/comment lines.

parse_ssh_config() {
    local f="$1"
    [[ -f "$f" ]] || { echo "Error: SSH config not found: $f" >&2; exit 1; }

    local in_host=false names="" user="" hval line trimmed key val

    _flush() { if [[ "$in_host" == true && -n "$names" ]]; then echo "${names%% *}|${user}"; fi; }

    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue

        if [[ "$trimmed" =~ ^[Mm]atch ]]; then
            _flush; in_host=false; names="" user=""; continue
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

# ── Fragment JSON builder ────────────────────────────────────────────────────
# Reads pipe-delimited records (name|user) from a file.
# Generates all GUIDs in a single python3 call using UUIDv5/UTF-16LE,
# matching the algorithm Windows Terminal uses for fragment profiles.
# Profile names are the full SSH host aliases (no prefix stripping).

build_fragment_json() {
    local records_file="$1"
    python3 - "$FRAGMENT_NAME" "$records_file" << 'PYEOF'
import uuid, hashlib, sys, json

def u5(ns, s):
    return uuid.UUID(
        bytes=hashlib.sha1(ns.bytes + s.encode('utf-16-le')).digest()[:16],
        version=5
    )

app_ns = u5(uuid.UUID('{f65ddb7e-706b-4499-8a50-40313caf510a}'), sys.argv[1])

profiles = []
with open(sys.argv[2]) as f:
    for line in f:
        parts = line.rstrip('\n').split('|')
        if not parts or not parts[0].strip():
            continue
        name = parts[0].strip()
        user = parts[1].strip() if len(parts) > 1 else ''
        guid = '{' + str(u5(app_ns, name)) + '}'
        cmd = ('ssh ' + user + '@' + name) if user else ('ssh ' + name)
        profiles.append({'name': name, 'commandline': cmd, 'guid': guid})

profiles.sort(key=lambda p: p['name'].casefold())
print(json.dumps({'profiles': profiles}, indent=2))
PYEOF
}

# ── newTabMenu entry builder ─────────────────────────────────────────────────
# Profiles without a dash in their name go to the top of the folder.
# Profiles with a dash are placed in sub-folders named after the prefix.
# All profiles are referenced by GUID so they are excluded from
# the remainingProfiles expansion (preventing them from showing up flat).

build_newtabmenu_entry() {
    printf '%s' "$1" | jq --arg name "$FRAGMENT_NAME" '
        (.profiles | map(select(.name | contains("-") | not))) as $direct |
        (.profiles | map(select(.name | contains("-")))
            | group_by(.name | split("-")[0])) as $groups |
        {
            "type": "folder",
            "name": $name,
            "entries": (
                ($direct | map({"type": "profile", "profile": .guid})) +
                ($groups | map({
                    "type": "folder",
                    "name": (.[0].name | split("-")[0]),
                    "entries": map({"type": "profile", "profile": .guid})
                }))
            )
        }
    '
}

# ── Path resolution ──────────────────────────────────────────────────────────

resolve_localappdata() {
    # Manual override wins unconditionally.
    if [[ -n "$LOCALAPPDATA_OVERRIDE" ]]; then
        echo "$LOCALAPPDATA_OVERRIDE"; return
    fi

    if command -v wslpath &>/dev/null; then
        local win_path=""

        # Try each Windows interop method in order; stop at first valid result.
        # Use || true so a missing binary doesn't trigger set -e.
        win_path="$(cmd.exe /C 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r\n')" || true
        # Reject unexpanded placeholder (cmd.exe not found or interop off)
        [[ "$win_path" == '%LOCALAPPDATA%' ]] && win_path=""

        if [[ -z "$win_path" ]]; then
            win_path="$(wslvar LOCALAPPDATA 2>/dev/null | tr -d '\r\n')" || true
        fi

        if [[ -z "$win_path" ]]; then
            win_path="$(powershell.exe -NoProfile -Command 'Write-Output $env:LOCALAPPDATA' 2>/dev/null | tr -d '\r\n')" || true
        fi

        if [[ -n "$win_path" ]]; then
            wslpath "$win_path"
            return
        fi
    fi

    # Git Bash / native Windows sets this directly.
    if [[ -n "${LOCALAPPDATA:-}" ]]; then
        echo "$LOCALAPPDATA"; return
    fi

    echo ""
}

resolve_settings_json() {
    local base
    base="$(resolve_localappdata)"
    [[ -z "$base" ]] && { echo ""; return; }
    for f in \
        "${base}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
        "${base}/Microsoft/Windows Terminal/settings.json" \
        "${base}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
    do
        [[ -f "$f" ]] && echo "$f" && return
    done
    echo ""
}

# ── JSONC comment stripper ───────────────────────────────────────────────────
# Removes // line comments and /* */ block comments while leaving strings alone.
# Also handles the Windows Terminal BOM (utf-8-sig).

strip_jsonc() {
    python3 -c '
import sys, re
txt = open(sys.argv[1], encoding="utf-8-sig").read()
txt = re.sub(r"(\"(?:[^\"\\\\]|\\\\.)*\")|//[^\n]*", lambda m: m.group(1) or "", txt)
txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.DOTALL)
sys.stdout.write(txt)
' "$1"
}

# ── settings.json updater ────────────────────────────────────────────────────
# Replaces (or inserts) our folder entry in newTabMenu.
# Preserves remainingProfiles so non-SSH profiles still appear.

update_settings_json() {
    local folder_entry="$1"
    local settings_file
    settings_file="$(resolve_settings_json)"

    if [[ -z "$settings_file" ]]; then
        echo "Warning: settings.json not found. Add this to newTabMenu manually:" >&2
        printf '%s\n' "$folder_entry" >&2
        return
    fi

    echo "  settings.json: $settings_file" >&2

    local clean_json
    if ! clean_json="$(strip_jsonc "$settings_file")"; then
        echo "Warning: Could not parse settings.json. Add this to newTabMenu manually:" >&2
        printf '%s\n' "$folder_entry" >&2
        return
    fi

    # Build the updated JSON first so we can validate it before touching the file.
    local updated_json
    if ! updated_json="$(printf '%s\n' "$clean_json" | jq \
        --argjson entry "$folder_entry" \
        --arg fname "$FRAGMENT_NAME" \
        '
        (.newTabMenu // [{"type": "remainingProfiles"}]) as $cur |
        (if ($cur | any(.[]; .type == "remainingProfiles")) then $cur
         else [{"type": "remainingProfiles"}] + $cur end) as $cur |
        .newTabMenu = (($cur | map(select(.type != "folder" or .name != $fname))) + [$entry])
        ')"; then
        echo "Warning: jq failed to process settings.json. Add this to newTabMenu manually:" >&2
        printf '%s\n' "$folder_entry" >&2
        return
    fi

    # Sanity-check: the updated JSON must contain our folder entry.
    if ! printf '%s\n' "$updated_json" | jq -e \
        --arg fname "$FRAGMENT_NAME" \
        '.newTabMenu // [] | any(.[]; .type == "folder" and .name == $fname)' \
        > /dev/null 2>&1; then
        echo "Warning: updated JSON is missing the folder entry — aborting write." >&2
        printf '%s\n' "$folder_entry" >&2
        return
    fi

    # Write to a temp file on the SAME Windows volume so mv is an atomic rename,
    # not a cross-filesystem copy (which can race with Windows Terminal).
    local tmp="${settings_file}.tmp.$$"
    if printf '%s\n' "$updated_json" > "$tmp" && mv "$tmp" "$settings_file"; then
        echo "  newTabMenu updated." >&2
    else
        rm -f "$tmp"
        echo "Warning: Failed to write settings.json. Add this to newTabMenu manually:" >&2
        printf '%s\n' "$folder_entry" >&2
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

echo "Reading SSH config: $SSH_CONFIG" >&2

records="$(parse_ssh_config "$SSH_CONFIG")"

if [[ -z "$records" ]]; then
    echo "No concrete hosts found in SSH config." >&2
    exit 0
fi

echo "Found $(printf '%s\n' "$records" | wc -l | tr -d ' ') host(s)" >&2

tmp="$(mktemp)"
printf '%s\n' "$records" > "$tmp"
fragment_json="$(build_fragment_json "$tmp")"
rm -f "$tmp"

if [[ "$DRY_RUN" == true ]]; then
    printf '%s\n' "$fragment_json"
    exit 0
fi

local_appdata="$(resolve_localappdata)"
if [[ -z "$local_appdata" ]]; then
    echo "Error: Cannot resolve Windows LOCALAPPDATA path." >&2
    echo "  Tried: cmd.exe, wslvar, powershell.exe — all unavailable or returned empty." >&2
    echo "  Fix:   pass it explicitly with -l / --localappdata, e.g.:" >&2
    echo "           $0 -l \"\$(wslpath 'C:\\Users\\<you>\\AppData\\Local')\"" >&2
    exit 1
fi

fragment_dir="${local_appdata}/Microsoft/Windows Terminal/Fragments/${FRAGMENT_NAME}"
fragment_file="${fragment_dir}/profiles.json"

mkdir -p "$fragment_dir"
printf '%s\n' "$fragment_json" > "$fragment_file"
echo "Fragment written: $fragment_file" >&2

folder_entry="$(build_newtabmenu_entry "$fragment_json")"

# Always write the newTabMenu entry as a standalone file so it can be
# copied manually into settings.json if the auto-update fails.
newtabmenu_file="${fragment_dir}/newTabMenu.json"
printf '%s\n' "$folder_entry" > "$newtabmenu_file"
echo "newTabMenu entry: $newtabmenu_file" >&2

update_settings_json "$folder_entry"

echo "" >&2
echo "Profiles:" >&2
printf '%s\n' "$fragment_json" | jq -r '.profiles[] | "  \(.name)  ->  \(.commandline)"' >&2
echo "" >&2
echo "Restart Windows Terminal to pick up the new profiles." >&2
