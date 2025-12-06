#!/usr/bin/env bash

# Convert MobaXterm .mxtsessions file into SSH config file

set -euo pipefail

LINE_LENGTH=60

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <moba_export_file> <output_ssh_config>"
    exit 1
fi

mobaFile="$1"
sshFile="$2"

# Clear the output file
: > "$sshFile"

echo "Parsing $mobaFile..."
echo "Generating SSH config to $sshFile..."

# Helper Functions ----------------------------------------

cleanSessionName() {
    local sessionName="$1"

    # Replace non-alphanumeric characters with underscore
    sessionName="${sessionName//[^a-zA-Z0-9._-]/_}"

    # Clean up weird combinations
    sessionName="${sessionName//_-_/-}"
    sessionName="${sessionName//__/_}"

    printf '%s' "${sessionName,,}"
}

# Check if the HostName indicates a real SSH target
isHostValid() {
    local host="$1"
    [[ -z "$host" ]] && return 1
    [[ "$host" == "-1" ]] && return 1
    [[ "$host" == *"__PIPE__"* ]] && return 1
    [[ "$host" == "0" ]] && return 1
    return 0
}

# Ensure Port is actually a number
isPortValid() {
    local port="$1"
    [[ -z "$port" ]] && return 1
    [[ "$port" =~ ^[0-9]+$ ]] && return 0
    return 1
}

sectionHeader=""

grep "=" "$mobaFile" | while IFS= read -r line; do
    # Remove Windows CR
    # line="${line//$'\r'/}"

    # Split into Key and Value
    key="${line%%=*}"
    value="${line#*=}"

    # SubRep (headers)
    if [[ "${key,,}" == "subrep" ]]; then
        cleanTitle="${value//[[:space:]]/}"
        if [[ -n "$cleanTitle" ]]; then
            bar=$(printf '%*s' "$LINE_LENGTH" '' | tr ' ' '#')
            sectionHeader=$(printf "\n%s\n# %s\n%s" "$bar" "${value^^}" "$bar")
        fi
        continue
    fi

    # Sessions (only lines with % in them)
    if [[ "$value" == *"%"* ]]; then

        IFS='%' read -r -a fields <<< "$value"

        # Field mapping based on MobaXterm export format
        # fields[1] = Host/IP
        # fields[2] = Port
        # fields[3] = User
        hostIp="${fields[1]:-}"
        portNum="${fields[2]:-}"
        userName="${fields[3]:-}"

        # Suppress Invalid Hosts
        if ! isHostValid "$hostIp"; then
            continue
        fi

        # Suppress Windows/RDP
        if [[ "$userName" == *"\\"* ]]; then
            continue
        fi

        # Suppress Local
        if [[ -z "$userName" || "$userName" == "-1" ]]; then
            continue
        fi

        # Port Validation
        if ! isPortValid "$portNum"; then
            portNum=""
        fi

        # Print the header if one is pending
        if [[ -n "$sectionHeader" ]]; then
            printf '%s\n\n' "$sectionHeader" >> "$sshFile"
            sectionHeader=""
        fi

        sessionName=$(cleanSessionName "$key")

        {
            printf "Host %s\n" "$sessionName"
            printf "    HostName %s\n" "$hostIp"
            printf "    User %s\n" "$userName"

            if [[ -n "$portNum" && "$portNum" != "22" ]]; then
                printf "    Port %s\n" "$portNum"
            fi

            printf "\n"
        } >> "$sshFile"

    fi
done

echo "Done! Check $sshFile for your config."
