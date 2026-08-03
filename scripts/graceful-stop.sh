#!/usr/bin/env bash
#
# graceful-stop.sh — save the Project Zomboid world to disk, THEN stop the stack.
#
# WHY THIS EXISTS
#   The danixu86 server image does NOT save on SIGTERM, so a plain
#   `docker compose stop` hard-kills the game and rolls the world back to the last
#   autosave / chunk-unload (this is what caused "items reset between restarts").
#   This script forces a save FIRST via RCON, confirms it worked, and only then
#   stops — so nothing is lost. See the notes in docker-compose.yaml.
#
# USAGE
#   ./scripts/graceful-stop.sh    # save, then stop pz + playit + autoheal
#   docker compose up -d          # bring it all back later
#
set -euo pipefail

# Run from the REPO ROOT (this script's parent), so `docker compose` always finds
# docker-compose.yaml + .env no matter where you call the script from.
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

# Small buffer so the save fully flushes before the containers go down
# (the server runs under emulation, so give it a moment).
sleep 5

echo "==> Stopping the stack (pz, playit, autoheal)..."
docker compose stop

echo ""
echo "==> Done. World is saved and the stack is stopped."
echo "    Bring it back online with:  docker compose up -d"

# A restart is exactly when Workshop mods get pulled fresh, and a mod update can
# rename its mod id — which silently breaks every client (see check-mods.sh). So
# report what the next boot will change WHILE you're still deciding to restart.
# Informational only: never block the stop, and never fail the script.
if [[ -x ./scripts/check-mods.sh ]]; then
  echo ""
  echo "==> Checking what the next start will pull from the Workshop..."
  ./scripts/check-mods.sh drift || true
fi
