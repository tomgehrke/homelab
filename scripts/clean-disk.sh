echo DISK CLEANUP ============================================

echo Before -----------------------
sudo df -H
echo

echo -- Cleaning up unused packages...
sudo apt autoremove
echo

echo Removing unused cached packages...
sudo apt autoclean
sudo apt clean
echo

echo Removing all but the last 3 days of system logs...
sudo journalctl --vacuum-time=3d
echo

echo Removing old Snap versions...
sudo snap set system refresh.retain=2
set -eu LANG=en_US.UTF-8
snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do sudo snap remove "$snapname" --revision="$revision"; done
echo

echo Docker cleanup...
docker system prune
echo

echo After ------------------------
sudo df -H
echo
echo DISK CLEANUP \| DONE! ==================================
