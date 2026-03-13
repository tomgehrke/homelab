#!/usr/bin/env bash

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
	DRY_RUN=true
	shift
fi

fileMask="$1"
sourceDirectory="$2"
archiveDirectory="$(echo "$3" | sed 's|/$||')"

find "$sourceDirectory" -type f -name "$fileMask" | while read -r file; do
	fileYear=$(date -r "$file" +"%Y")
	fileMonth=$(date -r "$file" +"%m")

	fileDestination="$archiveDirectory/$fileYear/$fileMonth"

	if $DRY_RUN; then
		echo "[dry-run] Would move: $file -> $fileDestination/"
	else
		mkdir -p "$fileDestination"
		mv "$file" "$fileDestination/"
		echo "Moved $file to $fileDestination"
	fi
done
