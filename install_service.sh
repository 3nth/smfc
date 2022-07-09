#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if cmp -s "${SCRIPT_DIR}/src/smfc.service" /etc/systemd/system/smfc.service
then
    echo "all good smfc service already enabled"
else
    echo "Installing Service..."
    pushd "${SCRIPT_DIR}"
    ./install.sh
    popd
    echo "Re-enabling smfc Service"
    systemctl enable smfc.service
    sleep 2
    systemctl start smfc.service
fi