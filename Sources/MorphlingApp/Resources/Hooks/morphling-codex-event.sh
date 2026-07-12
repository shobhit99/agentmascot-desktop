#!/bin/sh
: "${MORPHLING_PORT:=7824}"
curl -fsS --max-time 1 -H "Authorization: Bearer ${MORPHLING_TOKEN}" -H 'Content-Type: application/json' --data-binary @- "http://127.0.0.1:${MORPHLING_PORT}/v1/events" >/dev/null || true
