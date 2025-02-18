#!/usr/bin/env bash

runElevated() {
    [[ $EUID != 0 ]] && sudo "$@" || "$@"
}

divider() {
        dividerCharacter=$1
        printf "%0.s$dividerCharacter" {1..70}
        printf "\n"
}

echo
divider '='
echo Disk Cleanup
echo

divider '-'
echo Disk Usage: BEFORE
runElevated df -H | grep -v '^none'
echo

echo Cleaning up unused packages...
runElevated apt autoremove
echo

echo Removing unused cached packages...
runElevated apt autoclean
runElevated apt clean
echo

echo Removing all but the last 3 days of system logs...
runElevated journalctl --vacuum-time=3d
echo

if command -v snap >/dev/null 2>&1; then
        echo Removing old Snap versions...
        runElevated snap set system refresh.retain=2
        set -eu LANG=en_US.UTF-8
        snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do sudo snap remove "$snapname" --revision="$revision"; done
        echo
fi

if command -v docker >/dev/null 2>&1; then
        echo Docker cleanup...
        docker system prune
        echo
fi

divider '-'
echo Disk Usage: AFTER
runElevated df -H | grep -v '^none'
echo

echo 'DISK CLEANUP DONE!'
