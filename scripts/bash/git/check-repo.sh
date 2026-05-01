#!/usr/bin/env bash

checkRepo() {
        local skipFetch=false
        if [[ "$1" == "--skip-fetch" ]]; then
                skipFetch=true
                shift
        fi
        local repoPath="$1"
        local fetchResult
        local localStatus behindCount localBehind aheadCount localAhead

        local _r='' _green='' _yellow='' _red='' _cyan='' _dim=''
        if [[ -t 1 ]]; then
                _r=$'\e[0m' _green=$'\e[32m' _yellow=$'\e[33m'
                _red=$'\e[31m' _cyan=$'\e[36m' _dim=$'\e[2m'
        fi

        if [[ "$skipFetch" == false ]]; then
                git -C "$repoPath" fetch --quiet >/dev/null
                fetchResult=$?
                if [[ $fetchResult -gt 0 ]]; then
                        return $fetchResult
                fi
        fi

        git -C "$repoPath" diff --quiet          || localStatus+=" UNSTAGED"
        git -C "$repoPath" diff --cached --quiet || localStatus+=" UNCOMMITTED"
        [[ -n "$(git -C "$repoPath" ls-files --others --exclude-standard)" ]] \
                && localStatus+=" UNTRACKED"

        if git -C "$repoPath" rev-parse --abbrev-ref --symbolic-full-name @{u} &>/dev/null; then
                local currentBranch upstreamRef
                currentBranch=$(git -C "$repoPath" symbolic-ref --quiet --short HEAD)
                upstreamRef=$(git -C "$repoPath" for-each-ref --format='%(upstream:short)' \
                        "refs/heads/$currentBranch")
        fi

        if [[ -n "$upstreamRef" ]]; then
                behindCount=$(git -C "$repoPath" rev-list --count "$currentBranch..$upstreamRef")
                aheadCount=$(git -C "$repoPath" rev-list --count "$upstreamRef..$currentBranch")
                [[ "$behindCount" =~ ^[0-9]+$ && "$behindCount" -gt 0 ]] && localBehind=true
                [[ "$aheadCount"  =~ ^[0-9]+$ && "$aheadCount"  -gt 0 ]] && localAhead=true
        fi

        local repoName
        repoName=$(basename "$repoPath")

        printf "  ${_cyan}%-20s${_r}" "$repoName"
        if [[ -z "$localStatus" && "$localBehind" != true && "$localAhead" != true ]]; then
                printf "  ${_green}✓${_r}\n"
        else
                [[ -n "$localStatus" ]]     && printf "  ${_yellow}⚠%s${_r}" "$localStatus"
                [[ "$localBehind" = true ]] && printf "  ${_red}↓ %d${_r}" "$behindCount"
                [[ "$localAhead"  = true ]] && printf "  ${_yellow}↑ %d${_r}" "$aheadCount"
                printf "\n"
        fi

        if [[ "$localBehind" = true ]]; then
                printf "  ${_dim}Pull %s? (%d behind) [y/N]:${_r} " "$repoName" "$behindCount"
                read -r response
                [[ "${response,,}" = "y" ]] && git -C "$repoPath" pull
                echo
        fi

        if [[ "$localAhead" = true ]]; then
                printf "  ${_dim}Push %s? (%d ahead) [y/N]:${_r} " "$repoName" "$aheadCount"
                read -r response
                [[ "${response,,}" = "y" ]] && git -C "$repoPath" push
                echo
        fi
}

if [[ $- = *i* && "${BASH_SOURCE[0]}" = "$0" ]]; then
        checkRepo "$1"
fi
