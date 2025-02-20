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

rgb_to_ansi256() {
    local red=$1 green=$2 blue=$3
    if ((red == green && green == blue)); then
        # Convert grayscale
        if ((red < 8)); then echo 16; return; fi
        if ((red > 248)); then echo 231; return; fi
        echo $((232 + (red - 8) / 10))
    else
        # Convert RGB cube
        local ansi_red=$(( (red * 5) / 255 ))
        local ansi_green=$(( (green * 5) / 255 ))
        local ansi_blue=$(( (blue * 5) / 255 ))
        echo $((16 + (ansi_red * 36) + (ansi_green * 6) + ansi_blue))
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

# Convert RGB to ANSI 256 color
ansiColor=$(rgb_to_ansi256 $rValue $gValue $bValue)

# Set colors using `tput`
bgCode=$(tput setab $ansiColor)
trimCode=$(tput setaf $ansiColor)

# Set the foreground color based on brightness
if [[ $lValue -gt 128 ]]; then
    fgCode=$(tput setaf 0)  # Black text for bright backgrounds
else
    fgCode=$(tput setaf 15) # White text for dark backgrounds
fi

# Reset formatting
resetColor=$(tput sgr0)

# Construct the prompt with the background and foreground colors
PROMPT_COMMAND='PS1_CMD1=$(__git_ps1 " (%s) ")'
PS1='\n'"${trimCode}"'╭'"${resetColor}${bgCode}${fgCode}"' \u@\H '"${resetColor}"'$(tput setaf 3)$(tput setab 4)${PS1_CMD1}'"${resetColor}"' $(tput setaf 7)$(tput setab 232)\w'"${resetColor}"' \n'"${trimCode}"'╰'"${resetColor}"' \d \T > '

# Export the modified PS1
export PS1
