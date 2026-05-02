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

human_bytes() {
	awk -v b="$1" 'BEGIN{
		if      (b >= 1073741824) printf "%.1f GB", b/1073741824
		else if (b >= 1048576)    printf "%.1f MB", b/1048576
		else if (b >= 1024)       printf "%.1f KB", b/1024
		else                      printf "%d B",    b
	}'
}

fs_used() {
	df -B1 "${1:-/}" 2>/dev/null | awk 'NR==2{print $3+0}'
}

dir_bytes() {
	runElevated du -sb "$1" 2>/dev/null | awk '{print $1+0}'
}

freed_msg() {
	local freed=$1
	(( freed > 0 )) && echo "  freed $(human_bytes $freed)" || echo "  nothing to reclaim"
}

echo
divider '='
echo "Disk Cleanup$($DRY_RUN && echo ' (DRY RUN — no changes will be made)')"
echo

# Snapshot all filesystems now for final recovery total
declare -A _fs_before
while read -r mount used; do
	_fs_before["$mount"]=$used
done < <(runElevated df -B1 | grep -v '^none' | awk 'NR>1{print $6, $3}')

# --- Unused packages ---
echo "Removing unused packages..."
if $DRY_RUN; then
	runElevated apt autoremove --simulate 2>/dev/null \
		| grep -E "(will be REMOVED|^[0-9]+ upgraded)" | sed 's/^/  /'
else
	_b=$(fs_used /)
	runElevated apt autoremove -y >/dev/null 2>&1
	freed_msg $(( _b - $(fs_used /) ))
fi
echo

# --- Apt package cache ---
echo "Removing cached packages..."
if $DRY_RUN; then
	_sz=$(dir_bytes /var/cache/apt/archives)
	echo "  cache holds $(human_bytes $_sz)"
else
	_b=$(dir_bytes /var/cache/apt/archives)
	runElevated apt autoclean >/dev/null 2>&1
	runElevated apt clean >/dev/null 2>&1
	freed_msg $(( _b - $(dir_bytes /var/cache/apt/archives) ))
fi
echo

# --- Journal vacuum ---
echo "Vacuuming system logs (keeping 3 days)..."
if $DRY_RUN; then
	runElevated journalctl --disk-usage 2>/dev/null | sed 's/^/  /'
else
	_b=$(dir_bytes /var/log/journal)
	runElevated journalctl --vacuum-time=3d >/dev/null 2>&1
	freed_msg $(( _b - $(dir_bytes /var/log/journal) ))
fi
echo

# --- Snap old revisions ---
if command -v snap >/dev/null 2>&1; then
	echo "Removing old snap revisions..."
	if $DRY_RUN; then
		_disabled=$(LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print "  " $1 " (rev." $3 ")"}')
		[[ -n "$_disabled" ]] && echo "$_disabled" || echo "  no disabled revisions"
	else
		_b=$(dir_bytes /var/lib/snapd/snaps)
		runElevated snap set system refresh.retain=2
		LANG=en_US.UTF-8 snap list --all | awk '/disabled/{print $1, $3}' \
			| while read -r snapname revision; do
				runElevated snap remove "$snapname" --revision="$revision" >/dev/null 2>&1
			done
		freed_msg $(( _b - $(dir_bytes /var/lib/snapd/snaps) ))
	fi
	echo
fi

# --- Docker ---
if command -v docker >/dev/null 2>&1; then
	echo "Docker cleanup..."
	if $DRY_RUN; then
		docker system df
	else
		_reclaimed=$(docker system prune -f 2>/dev/null \
			| grep "Total reclaimed space" \
			| grep -oE '[0-9]+(\.[0-9]+)? ?[kKmMgGtT]?B')
		[[ -n "$_reclaimed" ]] && echo "  freed $_reclaimed" || echo "  nothing to prune"
	fi
	echo
fi

# --- Final summary ---
divider '-'

declare -A _fs_after
while read -r mount used; do
	_fs_after["$mount"]=$used
done < <(runElevated df -B1 | grep -v '^none' | awk 'NR>1{print $6, $3}')

_total_freed=0
for mount in "${!_fs_before[@]}"; do
	[[ -n "${_fs_after[$mount]}" ]] || continue
	_delta=$(( ${_fs_before[$mount]} - ${_fs_after[$mount]} ))
	(( _delta > 0 )) && _total_freed=$(( _total_freed + _delta ))
done

echo "Current Disk Usage:"
runElevated df -H | grep -v '^none'
echo

if $DRY_RUN; then
	echo "DRY RUN COMPLETE — no changes were made."
else
	(( _total_freed > 0 )) \
		&& echo "Total space recovered: $(human_bytes $_total_freed)" \
		|| echo "No space recovered."
fi
echo
