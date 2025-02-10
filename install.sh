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

echo "========================================================================="
echo "Checking prerequisites..."
checkPrerequisites

echo "========================================================================="
echo "Linking scripts..."
symlink "$PWD/scripts" ~/scripts

# Add sudoer
echo "========================================================================="
echo "Adding sudoer..."
if [[ -f ~/scripts/add-sudoer.sh ]]; then
    ~/scripts/add-sudoer.sh
fi

# Install homelab CA cert
echo "========================================================================="
echo "Installing homelab certificate authority..."
if [[ -f ~/homelab_priv/certs/install-homelab_certificate_authority.sh ]]; then
    ~/homelab_priv/certs/install-homelab_certificate_authority.sh
fi

# Link dotfiles
echo "========================================================================="
echo "Linking dotfiles..."
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
