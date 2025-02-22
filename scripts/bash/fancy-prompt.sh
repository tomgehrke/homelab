#!/usr/bin/env bash

# ==============================================================
# fancy-prompt.sh
#
# Makes your bash prompt fancy!
#
# NOTE: If colors seem off or adjacent characters don't blend
#       when they should, check your terminal to see if any
#       color/contrast correction is being automatically
#       applied. This is generally done to improve legibility
#       in certain cases.
# ==============================================================

ANSI_START="\e["
ANSI_FG="38;2;"
ANSI_BG="48;2;"
ANSI_END="m"
ANSI_BOLD="\e[1m"
ANSI_RESET="\e[0m"

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

getRGBValue() {
    local input="$1"
    local sanitized=$(echo "$input" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z')  # Clean input
    local length=${#sanitized}

    # If the cleaned string is empty, return a default color
    if [ "$length" -eq 0 ]; then
        echo "16;16;16"  # Black
        return
    fi

    # Initialize RGB values
    local r=0
    local g=0
    local b=0

    # Iterate over characters and accumulate RGB values
    for (( i=0; i<length; i++ )); do
        local char_value=$(printf "%d" "'${sanitized:i:1}")  # ASCII value
        r=$(( (r + char_value) % 240 ))  # Red component
        g=$(( (g + char_value * 2) % 240 ))  # Green component
        b=$(( (b + char_value * 3) % 240 ))  # Blue component
    done

    # Never less than 16
    (( r < 16 )) && (( r += 16 ))
    (( g < 16 )) && (( g += 16 ))
    (( b < 16 )) && (( b += 16 ))

    echo "$r;$g;$b"
}

getLuminosity() {
    local r=$1 g=$2 b=$3
    local luminosity

    # Multiply by 1000 to keep precision
    luminosity=$(( (2126 * r + 7152 * g + 722 * b) / 10000 ))

    echo "$luminosity"
}

# Get the hostname
host="${HOSTNAME:-$(command -v hostname && hostname || echo "$NAME")}"
hostRGB=$(getRGBValue $host)
luminosity=$(getLuminosity ${host//;/ })

infoFG="255;255;255"
if (( luminosity > 128 )); then
    infoFG="0;0;0"
fi

# Set the background and trim color based on RGB values
infoCode="${ANSI_START}${ANSI_BG}$hostRGB;${ANSI_FG}$infoFG${ANSI_END}"
trimCode="${ANSI_START}${ANSI_FG}$hostRGB${ANSI_END}"
gitCode="${ANSI_START}${ANSI_BG}0;0;255;${ANSI_FG}255;255;0${ANSI_END}"
workingDirCode="${ANSI_START}${ANSI_BG}0;0;0;${ANSI_FG}255;255;255${ANSI_END}"

# Add sudo user
if [[ -n $SUDO_USER ]]; then
        sudoUser=" ($SUDO_USER)"
fi

# Set flag
if [[ -n $FP_FLAGLEVEL && -n $FP_FLAGCAPTION ]]; then
        flag=$(getFlag "$FP_FLAGLEVEL" "$FP_FLAGCAPTION")
fi

# Construct the prompt with the background and foreground colors
PROMPT_COMMAND='PS1_CMD1=$(__git_ps1 " (%s) ")'
PS1='\n'"${trimCode}"'╭'"${ANSI_RESET}${infoCode}"' \u'"${sudoUser}"' on \H '"${ANSI_RESET}${gitCode}"'${PS1_CMD1}'"${ANSI_RESET}${flag}${workingDirCode}"' \w '"${ANSI_RESET}"'\n'"${trimCode}"'╰─┤'"${ANSI_RESET}"' \d \T '"${trimCode}"'│'"${ANSI_RESET}"' '

# Export the modified PS1
export PS1
