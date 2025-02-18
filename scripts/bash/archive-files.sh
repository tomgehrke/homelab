#!/bin/bash

fileMask="$1"
sourceDirectory="$2"
archiveDirectory="$(echo $3 | sed 's|/$||')"

# Find files ending with .m* and process them
find "$sourceDirectory" -type f -name "$fileMask" | while read -r file; do
  # Get the file creation date (year and month)
  fileYear=$(date -r "$file" +"%Y")
  fileMonth=$(date -r "$file" +"%m")

  fileDestination="$archiveDirectory/$fileYear/$fileMonth"
  mkdir -p "$fileDestination"

  # Move the file to the destination directory
  mv "$file" "$fileDestination/"
  echo "Moved $file to $fileDestination"
done
