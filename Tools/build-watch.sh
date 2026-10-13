#!/bin/bash
# Lets Claude start builds while you're away from the keyboard. Leave it
# running in a Terminal window; press Control-C to stop it.
#
# It only ever runs Tools/build-check.sh, and only when build/request appears.
# Nothing inside the request file is executed.
#
#   bash Tools/build-watch.sh
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
echo "idle" > build/status
echo "Watching for build requests. Press Control-C to stop."
while true; do
    date +%s > build/heartbeat
    if [ -f build/request ]; then
        token=$(head -c 40 build/request | tr -cd 'A-Za-z0-9_-')
        rm -f build/request
        echo "running $token" > build/status
        echo "[$(date +%H:%M:%S)] Build $token started"
        bash Tools/build-check.sh > build/check.out 2>&1
        sed 's/^/    /' build/summary.txt
        echo "done $token" > build/status
        echo "[$(date +%H:%M:%S)] Build $token finished"
    fi
    sleep 2
done
