#!/bin/bash

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
	DRY_RUN=true
	shift
fi

targetDirectory="$1"
maxAge="$2"
logFilePath="$3"

if [ ! -d "$targetDirectory" ]; then
	echo "Directory \"$targetDirectory\" does not exist!"
	exit 1
fi

if ! $DRY_RUN; then
	if [ ! -d "$(dirname "$logFilePath")" ]; then
		mkdir -p "$(dirname "$logFilePath")"
	fi

	if [ ! -f "$logFilePath" ]; then
		echo "Timestamp,Path,Size(MB),Type,CreationDate" > "$logFilePath"
	fi
fi

# Find and process files and directories older than maxAge days
find "$targetDirectory" -mindepth 1 -mtime "$maxAge" -print0 | while IFS= read -r -d '' item; do
	# Get the size of the item
	size=$(du -sm "$item" | cut -f1)

	# Determine if it's a file or directory
	if [ -f "$item" ]; then
		type="File"
	elif [ -d "$item" ]; then
		type="Directory"
	else
		type="Unknown"
	fi

	# Get creation date and age
	creation_date=$(stat -c %y "$item" | cut -d. -f1)

	if $DRY_RUN; then
		echo "[dry-run] Would delete: $item ($type, ${size}MB, modified $creation_date)"
	else
		# Log the item details
		echo "$(date '+%Y-%m-%d %H:%M:%S'),$item,$size,$type,$creation_date" >> "$logFilePath"

		# Delete the item
		rm -rf "$item"
	fi
done

if $DRY_RUN; then
	echo "Dry run complete. No files were deleted."
else
	echo "Cleanup complete. Results logged to $logFilePath"
fi
