#!/usr/bin/env bash
# Extract the earliest valid EXIF date from an image file.
# Supports JPEG and TIFF. PNG is attempted but unsupported officially.
# Uses exiftool when available; falls back to binary grep over first 16 KB.
# Outputs: YYYY:MM:DD HH:MM:SS on stdout, or an error on stderr with exit 1.

set -euo pipefail

REQUIRED_CMDS=(xxd grep head)

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        echo "Error: missing required commands: ${missing[*]}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# File type detection via magic bytes
# ---------------------------------------------------------------------------
get_file_type() {
    local magic
    magic=$(xxd -l 4 -p "$1" 2>/dev/null | tr -d '[:space:]')
    case "${magic:0:6}" in
        ffd8ff) echo "jpeg"; return ;;
    esac
    case "$magic" in
        89504e47)     echo "png";  return ;;
        49492a00)     echo "tiff"; return ;;  # little-endian TIFF
        4d4d002a)     echo "tiff"; return ;;  # big-endian TIFF
    esac
    echo "unknown"
}

# ---------------------------------------------------------------------------
# EXIF presence check — looks for the "Exif" ASCII marker in first 64 KB
# ---------------------------------------------------------------------------
has_exif() {
    grep -qa "Exif" "$1"
}

# ---------------------------------------------------------------------------
# Date extraction — three strategies, tried in order:
#
# 1. exiftool: reads DateTimeOriginal by tag name — no false positives.
#
# 2. XMP label search: XMP is XML text embedded in the JPEG, so the field
#    name (e.g. "DateTimeOriginal") appears as a literal string immediately
#    before the value. Handles both ISO 8601 (YYYY-MM-DDTHH:MM:SS) and EXIF
#    colon format (YYYY:MM:DD HH:MM:SS). No ambiguity about which date is
#    which — the label tells us directly.
#
# 3. Binary grep, metadata only: finds the JPEG SOS marker (FF DA) which
#    marks the start of entropy-coded scan data (the source of false
#    positives), then greps only the bytes before it. Uses earliest-date
#    heuristic as last resort.
# ---------------------------------------------------------------------------
extract_raw_dates() {
    local file="$1"

    # Strategy 1: exiftool
    if command -v exiftool &>/dev/null; then
        exiftool -DateTimeOriginal -DateTime -DateTimeDigitized \
                 -d "%Y:%m:%d %H:%M:%S" -s3 "$file" 2>/dev/null || true
        return
    fi

    # Strategy 2: labeled DateTimeOriginal in XMP text
    local labeled
    # ISO 8601 variant: YYYY-MM-DDTHH:MM:SS
    labeled=$(grep -aoa 'DateTimeOriginal[^0-9]\{0,20\}[12][0-9]\{3\}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]' \
              "$file" 2>/dev/null \
              | grep -oa '[12][0-9]\{3\}-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]' \
              | head -1)
    if [[ -n "$labeled" ]]; then
        # Convert ISO 8601 → EXIF colon format
        echo "${labeled:0:4}:${labeled:5:2}:${labeled:8:2} ${labeled:11:8}"
        return
    fi
    # EXIF colon format variant: YYYY:MM:DD HH:MM:SS
    labeled=$(grep -aoa 'DateTimeOriginal[^0-9]\{0,20\}[12][0-9]\{3\}:[0-1][0-9]:[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]' \
              "$file" 2>/dev/null \
              | grep -oa '[12][0-9]\{3\}:[0-1][0-9]:[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]' \
              | head -1)
    if [[ -n "$labeled" ]]; then
        echo "$labeled"
        return
    fi

    # Strategy 3: binary grep, stop before JPEG scan data
    # Find the SOS marker (FF DA) to avoid entropy-coded image bytes.
    local sos_hex_pos read_bytes
    sos_hex_pos=$(xxd -l 65536 -p "$file" 2>/dev/null \
                  | tr -d '\n' \
                  | grep -bo 'ffda' 2>/dev/null \
                  | head -1 \
                  | cut -d: -f1)
    if [[ -n "$sos_hex_pos" ]]; then
        read_bytes=$(( sos_hex_pos / 2 ))  # hex offset → byte offset
    else
        read_bytes=65536
    fi

    head -c "$read_bytes" "$file" 2>/dev/null \
        | grep -oa '[12][0-9]\{3\}:[0-1][0-9]:[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]' \
        || true
}

# ---------------------------------------------------------------------------
# Date validation — format already matched by grep pattern above,
# but values still need range checks.
# Uses 10# prefix to force decimal interpretation of zero-padded numbers.
# ---------------------------------------------------------------------------
validate_date() {
    local date="$1"
    [[ "$date" =~ ^([0-9]{4}):([0-9]{2}):([0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})$ ]] || return 1
    local year=${BASH_REMATCH[1]} month=${BASH_REMATCH[2]} day=${BASH_REMATCH[3]}
    local hour=${BASH_REMATCH[4]}  min=${BASH_REMATCH[5]}   sec=${BASH_REMATCH[6]}
    (( 10#$year  >= 1990 && 10#$year  <= 2038 )) || return 1
    (( 10#$month >= 1    && 10#$month <= 12   )) || return 1
    (( 10#$day   >= 1    && 10#$day   <= 31   )) || return 1
    (( 10#$hour  <= 23                        )) || return 1
    (( 10#$min   <= 59                        )) || return 1
    (( 10#$sec   <= 59                        )) || return 1
    return 0
}

# ---------------------------------------------------------------------------
# Pick the earliest valid date from stdin lines.
# DateTimeOriginal <= DateTime (modify date) for any real camera/editor,
# so the earliest candidate is the capture date we want.
# ---------------------------------------------------------------------------
earliest_valid_date() {
    local earliest=""
    while IFS= read -r date; do
        [[ -z "$date" ]] && continue
        validate_date "$date" || continue
        if [[ -z "$earliest" || "$date" < "$earliest" ]]; then
            earliest="$date"
        fi
    done
    [[ -n "$earliest" ]] && echo "$earliest"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local file="$1"

    # Input validation
    [[ -e "$file" ]] || { echo "Error: not found: $file"           >&2; return 1; }
    [[ -f "$file" ]] || { echo "Error: not a regular file: $file"  >&2; return 1; }
    [[ -r "$file" ]] || { echo "Error: permission denied: $file"   >&2; return 1; }
    [[ -s "$file" ]] || { echo "Error: file is empty: $file"       >&2; return 1; }

    check_deps || return 1

    local filetype
    filetype=$(get_file_type "$file")

    case "$filetype" in
        jpeg|tiff) ;;
        png)
            echo "Warning: PNG EXIF support is best-effort" >&2
            ;;
        unknown)
            echo "Error: unsupported file type (expected JPEG, TIFF, or PNG)" >&2
            return 1
            ;;
    esac

    if ! has_exif "$file"; then
        echo "Error: no EXIF data found in $file" >&2
        return 1
    fi

    local best
    best=$(extract_raw_dates "$file" | earliest_valid_date)

    if [[ -z "$best" ]]; then
        echo "Error: no valid date found in EXIF data of $file" >&2
        return 1
    fi

    echo "$best"
}

# Allow sourcing without running main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "Usage: $(basename "$0") <image-file>" >&2
        echo "Outputs EXIF date as YYYY:MM:DD HH:MM:SS, exits 1 on failure" >&2
        exit 1
    fi
    main "$1"
fi
