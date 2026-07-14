#!/bin/sh
# Agent Mascot managed hook. Lifecycle calls never block the agent.
: "${AGENT_MASCOT_PORT:=7824}"
curl -fsS --max-time 1 -H "Authorization: Bearer ${AGENT_MASCOT_TOKEN}" -H 'Content-Type: application/json' --data-binary @- "http://127.0.0.1:${AGENT_MASCOT_PORT}/v1/events" >/dev/null || true
