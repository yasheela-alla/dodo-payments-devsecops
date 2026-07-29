#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$PATH"
B=$(printf '\033[1;36m'); X=$(printf '\033[0m')
echo "${B}### Built ledger-api images (hardened 0.1.0 + pentest target :vuln) ###${X}"
echo "\$ docker images | grep -E 'REPOSITORY|ledger-api'"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' \
  | grep -E 'REPOSITORY|ledger-api'
sleep 2
