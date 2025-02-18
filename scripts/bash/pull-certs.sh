#!/usr/bin/env bash

connection="$1"
serverName="$2"

initializeCertData() {
    certCN=""
    certKey=""
}

certData=$(openssl s_client -connect $connection -servername $serverName -showcerts </dev/null)

while read -r lineData; do
        if [[ -z $certCN ]]; then
                certCN=$(echo "$lineData" | grep -oP "CN = \K.*")
                certCN=${certCN// /.}
        fi

        if [[ "$lineData" == "-----BEGIN CERTIFICATE-----" ]]; then
                certKey="$lineData\n"
                continue
        fi

        certKey+="$lineData\n"

        if [[ "$lineData" == "-----END CERTIFICATE-----" ]]; then
                echo -e "$certKey" > "$certCN.crt"

                initializeCertData
        fi
done <<< "$certData"

echo "$certData"
