#!/usr/bin/env bash

# Git support
source ~/.git-prompt

GIT_PS1_SHOWDIRTYSTATE=yes
GIT_PS1_SHOWUNTRACKEDFILES=yes
GIT_PS1_SHOWUPSTREAM=auto
GIT_PS1_SHOWCONFLICTSTATE=yes

getValue() {
    local charValue=$1
    local minValue=$(printf "%d" "'A")
    local maxValue=$(printf "%d" "'Z")
    local range=$(( maxValue - minValue ))
    local value=$(( (charValue - minValue) * 255 / range ))

    echo $value
}

# Function to convert RGB values to ANSI 256-color code
rgb_to_ansi256() {
    local r=$1 g=$2 b=$3
    if ((r == g && g == b)); then
        # Convert grayscale
        if ((r < 8)); then echo 16; return; fi
        if ((r > 248)); then echo 231; return; fi
        echo $((232 + (r - 8) / 10))
    else
        # Convert RGB cube
        local ansi_r=$(( (r * 5) / 255 ))
        local ansi_g=$(( (g * 5) / 255 ))
        local ansi_b=$(( (b * 5) / 255 ))
        local ansi_value=$((16 + (ansi_r * 36) + (ansi_g * 6) + ansi_b))
        # Return multiple of 16
        echo $(( (ansi_value + 8) / 16 * 16 ))
    fi
}

# Get the hostname or fallback to another command
host="${HOSTNAME:- $(command -v hostname && hostname || echo "$NAME")}"
host="${host^^}"
host="${host//[^A-Z]/}"

# R, G, and B values from the hostname
rValue=$(getValue $(printf "%d" "'${host:0:1}"))
gValue=$(getValue $(printf "%d" "'${host:1:1}"))
bValue=$(getValue $(printf "%d" "'${host:2:1}"))

# Luminosity (brightness) value
lValue=$(( ((rValue * 299) + (gValue * 587) + (bValue * 114)) / 1000 ))

# Set the background and trim color based on RGB values
bgCode="\e[48;5;$(rgb_to_ansi256 $rValue $gValue $bValue)m"
trimCode="\e[38;5;$(rgb_to_ansi256 $rValue $gValue $bValue)m"
fgCode="\e[1m\e[38;5;195m"  # Use white text for dark backgrounds

# If the background is bright, change the foreground to black
if [[ $lValue -gt 180 ]]; then
    fgCode="\e[38;5;0m"  # Use black text for bright backgrounds
fi

# Construct the prompt with the background and foreground colors
PROMPT_COMMAND='PS1_CMD1=$(__git_ps1 " (%s) ")'
PS1='\n'"${trimCode}"'╭'"\[\e[0m\]${bgCode}"' \u@\H \[\e[0m\]\[\e[33;44m\]${PS1_CMD1}\[\e[0m\]\[\e[97;48;5;232m\] \w \[\e[0m\]\n'"${trimCode}"'╰ \[\e[0m\] \d \T > '

# Export the modified PS1
export PS1
