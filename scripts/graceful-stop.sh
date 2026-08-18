#!/usr/bin/env bash
#
# Save the world to disk, THEN stop the stack.
#
# The server image does not save on SIGTERM, so a plain `docker compose stop`
# hard-kills the game and rolls the world back to the last autosave. That was the
# cause of "items reset between restarts".
#
set -euo pipefail

# Every path below is relative to the repo root.
cd "$(dirname "$0")/.."

echo "==> Flushing the world to disk (RCON 'save')..."
if docker compose run --rm rcon save; then
  echo "==> World saved."
else
  echo "" >&2
  echo "!! RCON save FAILED — the server may be down, still booting, or the RCON" >&2
  echo "!! password in .env may not match the server's. NOT stopping, because a" >&2
  echo "!! stop right now would roll the world back. Investigate first." >&2
  exit 1
fi

# Let the save finish flushing before the containers go down; the server runs
# under emulation, so give it a moment.
sleep 5

echo "==> Stopping the stack (pz, playit, autoheal)..."
docker compose stop

echo ""
echo "==> Done. World is saved and the stack is stopped."
echo "    Bring it back online with:  docker compose up -d"

# A restart is when Workshop mods get pulled fresh, and an update can rename a
# mod id and silently break every client. Report that while you're still deciding
# to restart. Informational only, never blocks the stop.
if [[ -x ./scripts/check-mods.sh ]]; then
  echo ""
  echo "==> Checking what the next start will pull from the Workshop..."
  ./scripts/check-mods.sh drift || true
fi
