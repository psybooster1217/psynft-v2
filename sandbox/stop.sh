#!/usr/bin/env bash
# Stop any sandbox processes (anvil + vite) left running, and clean the local env file.
set -uo pipefail

echo "▶ stopping sandbox…"
if command -v taskkill >/dev/null 2>&1; then
  # Windows / Git Bash
  taskkill //F //IM anvil.exe >/dev/null 2>&1 && echo "  anvil stopped" || echo "  no anvil running"
  # vite runs under node; only kill the process whose LOCAL address is :5173 (the server).
  # Matching any ':5173' would also hit browser tabs connected to it (foreign address :5173).
  for pid in $(netstat -ano 2>/dev/null | awk '$2 ~ /:5173$/ {print $NF}' | sort -u); do
    taskkill //F //PID "$pid" >/dev/null 2>&1 && echo "  vite (pid $pid) stopped"
  done
else
  pkill -f "anvil --chain-id 31337" 2>/dev/null && echo "  anvil stopped" || echo "  no anvil running"
  pkill -f "vite" 2>/dev/null && echo "  vite stopped" || true
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rm -f "$ROOT/ui/.env.local" && echo "  removed ui/.env.local"
echo "▶ done."
