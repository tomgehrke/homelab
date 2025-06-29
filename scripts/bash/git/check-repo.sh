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

        # Make sure we're on a branch with an upstream
        if git -C "$repoPath" rev-parse --abbrev-ref --symbolic-full-name @{u} &>/dev/null; then
            local currentBranch upstreamRef

            currentBranch=$(git -C "$repoPath" symbolic-ref --quiet --short HEAD)
            upstreamRef=$(git -C "$repoPath" for-each-ref --format='%(upstream:short)' "refs/heads/$currentBranch")
        fi

        if [[ -n "$upstreamRef" ]]; then
                behindCount=$(git -C "$repoPath" rev-list --count "$currentBranch..$upstreamRef")
                aheadCount=$(git -C "$repoPath" rev-list --count "$upstreamRef..$currentBranch")

                [[ "$behindCount" =~ ^[0-9]+$ && "$behindCount" -gt 0 ]] && localBehind=true
                [[ "$aheadCount" =~ ^[0-9]+$ && "$aheadCount" -gt 0 ]] && localAhead=true
        fi

        # Report Results

        if [[ -n "$localStatus" ]]; then
                echo "=> ${repoPath} status: ${localStatus:2}"
        fi

        if [[ "$localBehind" = true ]]; then
                read -p "=> ${repoPath} needs updating. Would you like to do this now? (y/n): " response
                if [[ "${response,,}" = "y" ]]; then
                        git -C "$repoPath" pull
                fi
                echo
        fi

        if [[ "$localAhead" = true ]]; then
                read -p "=> ${repoPath} has local changes. Push to remote? (y/n): " response
                if [[ "${response,,}" = "y" ]]; then
                        git -C "$repoPath" push
                fi
                echo
        fi
}

if [[ $- = *i* && "${BASH_SOURCE[0]}" = "$0" ]]; then
        checkRepo "$1"
fi
