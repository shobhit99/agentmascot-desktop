#!/bin/bash
set -euo pipefail
curl -fsS http://127.0.0.1:7824/healthz | grep -q '"ok":true'
echo 'Bridge health: PASS'
