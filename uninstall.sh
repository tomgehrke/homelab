#!/usr/bin/env bash

# Tom's Homelab Support UNinstaller
# ===============================

divider() {
        dividerCharacter=$1
        printf "%0.s$dividerCharacter" {1..70}
        printf "\n"
}

echo
divider '='
echo Homelab support uninstaller
echo

# Unlink dotfiles
# Note this list may reference more than is found in the
# install script. This is to insure deprecated references
# are removed.
echo "Unlinking dotfiles..."
dotFiles=(
	bash_profile
	bashrc
	gitconfig
	nanorc
	ssh/config
	git-prompt
)
for dotFile in "${dotFiles[@]}"; do
	if [[ -L ~/.$dotFile ]]; then
	    rm ~/."$dotFile"
	fi
done

echo "Unlinking scripts..."
if [[ -L ~/scripts ]]; then
    rm ~/scripts
fi

# More cleanup of deprecated references
echo "Legacy cleanup..."
if [[ -L ~/.bash_homelab ]]; then
    rm ~/.bash_homelab
fi
if [[ -L ~/.homelab_aliases ]]; then
    rm ~/.homelab_aliases
fi

if [[ -f ~/.config/homelab/homelab.conf ]]; then
        read -p "Do you want to remove existing configuration? (y/n): " removeConfig
        removeConfig=${removeConfig,,}
        if [[ $removeConfig == 'y' ]]; then
                rm ~/.config/homelab/homelab.conf
        fi
fi

echo 'Uninstall complete!'
