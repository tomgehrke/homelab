#!/usr/bin/env bash

# Tom's Homelab Support Installer
# ===============================

symlink() {
	printf '%55s -> %s\n' "${1/#$HOME/\~}" "${2/#$HOME/\~}"
	ln -nsf "$@"
}

checkPrerequisites() {
        if ! command -v "jq" >/dev/null && command -v "apt" >/dev/null; then
                sudo apt install jq -y -q
        elif ! command -v "jq" >/dev/null && command -v "dnf" >/dev/null; then
                sudo dnf install jq -y -q
        fi
}

divider() {
        dividerCharacter=$1
        printf "%0.s$dividerCharacter" {1..70}
        printf "\n"
}

echo
divider '='
echo Homelab support installer
echo

echo Checking prerequisites...
checkPrerequisites

echo Linking scripts...
symlink "$PWD/scripts" ~/scripts

# Add sudoer if this is not root
if [[ $EUID != 0 && -f ~/scripts/add-sudoer.sh ]]; then
        echo Adding sudoer...
        ~/scripts/add-sudoer.sh
fi

# Install homelab CA cert
echo Installing Homelab certificate authority...
if [[ -f ~/homelab_priv/certs/install-homelab_certificate_authority.sh ]]; then
    ~/homelab_priv/certs/install-homelab_certificate_authority.sh
fi

# Link dotfiles
echo Linking dotfiles...
dotFiles=(
	bash_profile
	bashrc
	gitconfig
	nanorc
	git-prompt
)
for dotFile in "${dotFiles[@]}"; do
	[[ -d ~/.$dotFile && ! -L ~/.$dotFile ]]
	symlink "$PWD/dotfiles/$dotFile" ~/."$dotFile"
done

echo
echo 'Installation complete!'
echo

