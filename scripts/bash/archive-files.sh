#!/usr/bin/env bash

DRY_RUN=false
RECURSIVE=false

while [[ "${1:-}" == --* ]]; do
	case "$1" in
		--dry-run)   DRY_RUN=true   ;;
		--recursive) RECURSIVE=true ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
	shift
done

fileMask="$1"
sourceDirectory="$2"
archiveDirectory="$(echo "$3" | sed 's|/$||')"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXIF_DATE="$SCRIPT_DIR/exif-date.sh"

get_file_date() {
	local file="$1"
	local exifDate
	if [[ -x "$EXIF_DATE" ]] && exifDate=$("$EXIF_DATE" "$file" 2>/dev/null); then
		echo "${exifDate:0:4}" "${exifDate:5:2}"
	else
		echo "$(date -r "$file" +"%Y")" "$(date -r "$file" +"%m")"
	fi
}

findArgs=("$sourceDirectory")
$RECURSIVE || findArgs+=(-maxdepth 1)
findArgs+=(-type f -name "$fileMask")

find "${findArgs[@]}" | while read -r file; do
	read -r fileYear fileMonth < <(get_file_date "$file")

	fileDestination="$archiveDirectory/$fileYear/$fileMonth"

	if $DRY_RUN; then
		echo "[dry-run] Would move: $file -> $fileDestination/"
	else
		mkdir -p "$fileDestination"
		mv "$file" "$fileDestination/"
		echo "Moved $file to $fileDestination"
	fi
done
