#!/usr/bin/env bash

# mxt2ssh
#
# Convert MobaXterm .mxtsessions file into SSH config file
#
# by Tom Gehrke
# 2025.12.06

readonly LINE_LENGTH=60

usage() {
    more <<'EOF'
Usage: mxt2ssh [options]

Options:
    -i, --in <file>       MobaXterm export file (.mxtsessions)
    -o, --out <file>      Output SSH config file
    -p, --preview         Preview mode (print to stdout, no file written)
    -h, --help            Show this help message and exit

Examples:
    mxt2ssh -i sessions.mxtsessions -o ~/.ssh/config
    mxt2ssh --in my.mxtsessions --out ./ssh_config
    mxt2ssh -i export.mxtsessions --preview
EOF
    exit 0
}

moba_file=""
ssh_file=""
preview=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--in)
            moba_file="$2"
            shift 2
            ;;
        -o|--out)
            ssh_file="$2"
            shift 2
            ;;
        -p|--preview)
            preview=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# If a file wasn't passed, show usage
[[ -z "$moba_file" ]] && usage

# If we are not in preview mode and an output file was not passed, show usage
[[ $preview == false && -z "$ssh_file" ]] && usage

# Validate input file
if [[ ! -f "$moba_file" ]]; then
    echo "Error: Input file '$moba_file' does not exist." >&2
    exit 1
fi
if [[ ! -r "$moba_file" ]]; then
    echo "Error: Input file '$moba_file' is not readable." >&2
    exit 1
fi

# Track duplicate hostnames in memory
declare -A seen_hosts

# Generate header
header_bar=$(printf '%*s' "$LINE_LENGTH" '' | tr ' ' '#')
header_msg="# SSH config converted from: $moba_file"

if [[ $preview == true ]]; then
    echo "$header_bar"
    echo "$header_msg"
    echo "$header_bar"
else
    {
        echo "$header_bar"
        echo "$header_msg"
        echo "$header_bar"
        echo
    } > "$ssh_file"
    echo "Parsing $moba_file..."
    echo "Generating SSH config to $ssh_file..."
fi

clean_session_name() {
    local session_name="$1"
    session_name="${session_name//[^a-zA-Z0-9._-]/_}"
    session_name="${session_name//_-_/-}"
    session_name="${session_name//__/_}"
    printf '%s' "${session_name,,}"
}

is_host_valid() {
    local host="$1"
    [[ -z "$host" || "$host" == "-1" || "$host" == "0" || "$host" == *"__PIPE__"* ]] && return 1
    return 0
}

is_port_valid() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    return 0
}

section_header=""
count=0

# ANSI colors (only use if stdout is a terminal)
if [[ -t 1 ]]; then
    bold=$(tput bold)
    cyan=$(tput setaf 6)
    yellow=$(tput setaf 3)
    reset=$(tput sgr0)
else
    bold=""
    cyan=""
    yellow=""
    reset=""
fi

# Main parsing loop
while IFS= read -r line; do
    line="${line//$'\r'/}"
    key="${line%%=*}"
    value="${line#*=}"

    # Handle Section Headers (SubRep)
    case "${key,,}" in
        subrep)
            clean_title="${value//[[:space:]]/}"
            if [[ -n "$clean_title" ]]; then
                fill_len=$((LINE_LENGTH - 4))
                equals_str=$(printf '%*s' "$fill_len" '' | tr ' ' '=')
                bar="# $equals_str #"

                section_header=$(printf "\n%s\n# %s\n%s" "$bar" "${value^^}" "$bar")
            fi
            continue
            ;;
    esac

    [[ "$value" != *"%"* ]] && continue

    IFS='%' read -r -a fields <<< "$value"
    [[ ${#fields[@]} -lt 4 ]] && continue

    host_ip="${fields[1]}"
    port_num="${fields[2]}"
    user_name="${fields[3]}"

    if ! is_host_valid "$host_ip"; then continue; fi
    if [[ "$user_name" == *"\\"* || -z "$user_name" || "$user_name" == "-1" ]]; then continue; fi
    if ! is_port_valid "$port_num"; then port_num=""; fi

    # Write section header if pending
    if [[ -n "$section_header" ]]; then
        if [[ $preview == true ]]; then
            printf "%s%s%s\n\n" "$bold" "$section_header" "$reset"
        else
            printf '%s\n\n' "$section_header" >> "$ssh_file"
        fi
        section_header=""
    fi

    session_name=$(clean_session_name "$key")

    # Handle Duplicates
    base_name="$session_name"
    dup_count=1
    while [[ -n "${seen_hosts[$session_name]}" ]]; do
        ((dup_count++))
        session_name="${base_name}_${dup_count}"
    done
    seen_hosts["$session_name"]=1

    block="Host $session_name\n    HostName $host_ip\n    User $user_name"
    [[ -n "$port_num" && "$port_num" != "22" ]] && block+="\n    Port $port_num"
    block+="\n"

    if [[ $preview == true ]]; then
        printf "%s%b%s\n" "$cyan" "$block" "$reset"
    else
        printf "%b\n" "$block" >> "$ssh_file"
    fi

    ((count++))

done < <(grep "=" "$moba_file")

# Footer
footer="# End of converted config"
if [[ $preview == true ]]; then
    echo "$footer"
    echo "${yellow}Preview complete — $count sessions processed.${reset}"
else
    echo "$footer" >> "$ssh_file"
    echo "Done! Wrote $count sessions to $ssh_file"
fi
