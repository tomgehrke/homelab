#!/usr/bin/env bash

cd "${0%/*}"

echo Reinstalling homelab...
"$PWD/uninstall.sh"
"$PWD/install.sh"
