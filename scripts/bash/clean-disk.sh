#!/usr/bin/env bash

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

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
echo "Disk Cleanup${DRY_RUN:+ (DRY RUN — no changes will be made)}"
echo

divider '-'
echo "Disk Usage: BEFORE"
runElevated df -H | grep -v '^none'
echo

echo "Cleaning up unused packages..."
if $DRY_RUN; then
	runElevated apt autoremove --simulate
else
	runElevated apt autoremove
fi
echo

echo "Removing unused cached packages..."
if $DRY_RUN; then
	echo "[dry-run] Would run: apt autoclean && apt clean"
else
	runElevated apt autoclean
	runElevated apt clean
fi
echo

echo "Removing all but the last 3 days of system logs..."
if $DRY_RUN; then
	echo "[dry-run] Current journal disk usage:"
	runElevated journalctl --disk-usage
else
	runElevated journalctl --vacuum-time=3d
fi
echo

if command -v snap >/dev/null 2>&1; then
	echo "Removing old Snap versions..."
	if $DRY_RUN; then
		echo "[dry-run] Disabled snap revisions that would be removed:"
		LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print "  " $1 " (revision " $3 ")"}'
	else
		runElevated snap set system refresh.retain=2
		LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
			sudo snap remove "$snapname" --revision="$revision"
		done
	fi
	echo
fi

if command -v docker >/dev/null 2>&1; then
	echo "Docker cleanup..."
	if $DRY_RUN; then
		echo "[dry-run] Docker disk usage:"
		docker system df
	else
		docker system prune
	fi
	echo
fi

divider '-'
echo "Disk Usage: AFTER"
runElevated df -H | grep -v '^none'
echo

echo "DISK CLEANUP DONE!"
