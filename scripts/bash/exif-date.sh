#!/usr/bin/env bash
# Extract the earliest valid EXIF date from an image file.
# Supports JPEG and TIFF. PNG is attempted but unsupported officially.
# Outputs: YYYY:MM:DD HH:MM:SS on stdout, or an error on stderr with exit 1.

set -euo pipefail

REQUIRED_CMDS=(xxd dd grep head)

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
# Date string extraction
# Reads first 128 KB (covers all real-world EXIF segments) and greps for
# the EXIF ASCII date format: YYYY:MM:DD HH:MM:SS
# Leading digit restricted to 1 or 2 to reduce false positives.
# ---------------------------------------------------------------------------
extract_raw_dates() {
    head -c 131072 "$1" 2>/dev/null \
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
