#!/usr/bin/env bash

checkRepo() {
        local repoPath="$1"
        local fetchResult
        local localStatus behindCount localBehind aheadCount localAhead

        git -C "$repoPath" fetch --quiet
        fetchResult=$?
        if [[ $fetchResult -gt 0 ]]; then
                return $fetchResult
        fi

        # See if local repo has unstaged changes
        git -C "$repoPath" diff --quiet || localStatus="${localStatus}, UNSTAGED"

        # See if local repo has uncommitted changes
        git -C "$repoPath" diff --cached --quiet || localStatus="${localStatus}, UNCOMMITTED"

        # Check for untracked files
        [[ -n "$(git -C "$repoPath" ls-files --others --exclude-standard)" ]] && localStatus="${localStatus}, UNTRACKED"

        # See if local repo is behind
        behindCount=$(git -C "$repoPath" rev-list --quiet --count @..@{u})
        [[ "$behindCount" -gt 0 ]] && localBehind=true

        # See if local repo is ahead
        aheadCount=$(git -C "$repoPath" rev-list --quiet --count @{u}..@)
        [[ "$aheadCount" -gt 0 ]] && localAhead=true

        # Report Results

        if [[ -n "$localStatus" ]]; then
                echo "=> ${repoPath} status: ${localStatus:2}"
                echo
        fi

        if [[ "$localBehind" = true ]]; then
                read -p "=> ${repoPath} needs updating. Would you like to do this now? (y/n): " response
                if [[ "${response,,}" = "y" ]]; then
                        git -C "$repoPath" pull
                fi
        fi

        if [[ "$localAhead" = true ]]; then
                read -p "=> ${repoPath} has local changes. Push to remote? (y/n): " response
                if [[ "${response,,}" = "y" ]]; then
                        git -C "$repoPath" push
                fi
        fi
}

if [[ $- = *i* && "${BASH_SOURCE[0]}" = "$0" ]]; then
        checkRepo "$1"
fi
