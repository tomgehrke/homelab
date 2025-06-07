#!/usr/bin/env bash

checkRepo() {
        local repoPath="$1"
        local fetchResult
        local localUnstaged localUncommitted localBehind localAhead localUntracked
        local attentionRequired

        git -C "$repoPath" fetch --quiet
        fetchResult=$?
        if [[ $fetchResult -gt 0 ]]; then
                return $fetchResult
        fi

        # See if local repo has unstaged changes
        git -C "$repoPath" diff --quiet || localUnstaged=true

        # See if local repo has uncommitted changes
        git -C "$repoPath" diff --cached --quiet || localUncommitted=true

        # See if local repo is behind
        localBehind=$(git -C "$repoPath" rev-list --quiet --count @..@{u})
        [[ "$localBehind" -gt 0 ]] && localBehind=true

        # See if local repo is ahead
        localAhead=$(git -C "$repoPath" rev-list --quiet --count @{u}..@)
        [[ "$localAhead" -gt 0 ]] && localAhead=true

        # Check for untracked files
        [[ -n "$(git -C "$repoPath" ls-files --others --exclude-standard)" ]] && localUntracked=true

        # Report Results
        if [[ "$localUnstaged" == true ]]; then
                attentionRequired=true
                echo "==> ${repoPath} has unstaged changes."
        fi

        if [[ "$localUncommitted" == true ]]; then
                attentionRequired=true
                echo "==> ${repoPath} has staged but uncommitted changes."
        fi

        if [[ "$localUntracked" == true ]]; then
                attentionRequired=true
                echo "==> ${repoPath} has untracked files."
        fi

        if [[ "$localBehind" == true ]]; then
                attentionRequired=true
                read -p "==> ${repoPath} needs updating. Would you like to do this now? (y/n): " response
                if [[ "${response,,}" == "y" ]]; then
                        git -C "$repoPath" pull
                fi
        fi

        if [[ "$localAhead" == true ]]; then
                attentionRequired=true
                read -p "==> ${repoPath} has local changes. Push to remote? (y/n): " response
                if [[ "${response,,}" == "y" ]]; then
                        git -C "$repoPath" push
                fi
        fi

        if [[ "$attentionRequired" == true ]]; then
                echo
        fi

}

if [[ $- == *i* && "${BASH_SOURCE[0]}" == "$0" ]]; then
        checkRepo "$1"
fi
