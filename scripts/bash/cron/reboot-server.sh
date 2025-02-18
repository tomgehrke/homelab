#!/usr/bin/env bash

if [[ -z $1 ]]; then
        logDir="${0/*}/logs"
else
        logDir="$1"
fi

if [[ ! -d  "$logDir" ]]; then
        mkdir -p "$logDir"
fi

echo "$(date) - Rebooting server..." >> "$logDir/reboot-server.log"
shutdown -r now