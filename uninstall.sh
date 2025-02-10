#!/usr/bin/env bash

# Tom's Homelab Support UNinstaller
# ===============================

# Link dotfiles
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

echo "Legacy cleanup..."
if [[ -L ~/.bash_homelab ]]; then
    rm ~/.bash_homelab
fi
if [[ -L ~/.homelab_aliases ]]; then
    rm ~/.homelab_aliases
fi
