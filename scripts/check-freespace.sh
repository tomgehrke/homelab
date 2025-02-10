#!/bin/bash

thresholdPercentage=$1
highUsage=0
usageReport=""

if [[ ! "$thresholdPercentage" =~ ^[0-9]+$ ]]; then
  thresholdPercentage=80
fi

echo "Checking for mounts over $thresholdPercentage% used..."
dfOutput="$(df --human-readable --output=pcent,size,used,avail,source,target)"
while IFS= read -r line; do
  percentUsed=$(echo $line | grep -oP "^[0-9]{1,3}")

  if [[ -z "$percentUsed" ]]; then
    usageReport+="$line\n"
    continue
  fi

  if (( $percentUsed >= $thresholdPercentage )); then
    usageReport+="$line\n"
    highUsage=1
  fi
done <<< "$dfOutput"

if (( highUsage > 0 )); then
  echo
  echo "High Disk Usage!"
  echo "================"
  echo -e "$usageReport"
  exit 1
fi

echo "All clear!"
