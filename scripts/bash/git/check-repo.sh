#!/usr/bin/env bash

checkRepo() {
        local repoPath="$1"

        git --quiet -C "$repoPath" fetch origin

        # See if local repo has unstaged changes...
        if ! git -C "$repoPath" diff; then
                echo -e "Your Homelab repo has unstaged changes.\n"
        fi

        # See if local repo has uncommitted changes...
        if ! git -C "$repoPath" diff --cached; then
                echo -e "Your Homelab repo has staged but uncommited changes.\n"
        fi

        # See if local repo is behind...
        if (( $(git -C "$repoPath" rev-list --count @..@{u} ) > 0 )); then
                if read -p "Homelab repo needs updating. Would you like to do this now? (y/n): " response && [[ "${response,,}" == "y" ]]; then
                        git -C "$repoPath" pull
                fi
        fi

        # See if local repo is ahead...
        if (( $(git -C "$repoPath" rev-list --count @{u}..@ ) > 0 )); then
                if read -p "You have local Homelab changes. Push to remote? (y/n): " response && [[ "${response,,}" == "y" ]]; then
                        git -C "$repoPath" push
                fi
        fi
}

checkRepo "$1"
