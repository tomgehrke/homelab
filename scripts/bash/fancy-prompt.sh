#!/usr/bin/env bash

# Git support
source ~/.git-prompt

GIT_PS1_SHOWDIRTYSTATE=yes
GIT_PS1_SHOWUNTRACKEDFILES=yes
GIT_PS1_SHOWUPSTREAM=auto
GIT_PS1_SHOWCONFLICTSTATE=yes

getFlag() {
    local level="$1"
    local caption="$2"

    # Manually map background colors to their closest ANSI 256 equivalents
    case "$level" in
        1) bgColor="48;5;196"; trimColor="38;5;196"; fgColor="38;5;226" ;;
        2) bgColor="48;5;202"; trimColor="38;5;202"; fgColor="38;5;16" ;;
        3) bgColor="48;5;226"; trimColor="38;5;226"; fgColor="38;5;16" ;;
        4) bgColor="48;5;44";  trimColor="38;5;44"; fgColor="38;5;16" ;;
        5) bgColor="48;5;33";  trimColor="38;5;33"; fgColor="38;5;16" ;;
        *) echo "Invalid level"; return 1 ;;
    esac

    # Print the caption with background color
    echo -e "\e[${bgColor};${fgColor}m ${caption} \e[0m\e[48;5;16;${trimColor}m\e[0m"
}

getValue() {
    local input="$1"
    # Convert to uppercase and strip out non-A-Z characters
    local sanitized=$(echo "$input" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z')

    # Get the length of the cleaned string
    local length=${#sanitized}

    # If the cleaned string is empty, return 16 (minimum value)
    if [ "$length" -eq 0 ]; then
        echo 16
        return
    fi

    # Initialize sum
    local sum=0

    # Calculate weighted sum
    for (( i=0; i<length; i++ )); do
        local char_value=$(( $(printf "%d" "'${sanitized:i:1}") - 65))
        sum=$((sum + (char_value * length) ))
    done

    # Compute the average
    local avg=$((sum / length))

    # Normalize avg to 16-240 range
    result=$(((avg - 0) * (240 - 16) / (25 * length) + 16))

    # Round to nearest multiple of 16
    result=$(((result + 8) / 16 * 16))

    # Ensure it stays within the 16-240 range
    if [ "$result" -gt 240 ]; then
        result=240
    elif [ "$result" -lt 16 ]; then
        result=16
    fi

    echo "$result"
}

# Get the hostname
host="${HOSTNAME:-$(command -v hostname && hostname || echo "$NAME")}"

# Set the background and trim color based on RGB values
bgCode="\e[48;5;$(getValue $host)m"
trimCode="\e[38;5;$(getValue $host)m"

# Add sudo user
if [[ -n $SUDO_USER ]]; then
        sudoUser=" ($SUDO_USER)"
fi

# Set flag
if [[ -n $FANCYPROMPT_FLAGLEVEL && -n $FANCYPROMPT_FLAGCAPTION ]]; then
        flag=$(getFlag "$FANCYPROMPT_FLAGLEVEL" "$FANCYPROMPT_FLAGCAPTION")
fi

# Construct the prompt with the background and foreground colors
PROMPT_COMMAND='PS1_CMD1=$(__git_ps1 " (%s) ")'
PS1='\n'"${trimCode}"'╭'"\[\e[0m\]${bgCode}"' \u'"${sudoUser}"' on \H \[\e[0m\]\[\e[33;44m\]${PS1_CMD1}\[\e[0m\]'"${flag}"'\[\e[97;48;5;232m\] \w \[\e[0m\]\n'"${trimCode}"'╰─┤\[\e[0m\] \d \T \[\e[0m\]'"${trimCode}"'│\[\e[0m\] '

# Export the modified PS1
export PS1
