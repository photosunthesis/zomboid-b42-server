# 🧟 Project Zomboid Server (Build 42)

Run a Project Zomboid multiplayer server on your own computer and let friends join over the internet. No router setup, no static IP, no fussy install. Works on Mac (including Apple Silicon), Windows, or Linux.

Everything lives in two files: `docker-compose.yaml` (the setup, you don't touch it) and `.env` (your settings).

## 🧰 What you need

- A computer you can leave running while people play.
- About 8 GB of free RAM. Small group? You can drop it to 4 GB (see [Adjusting RAM](#adjusting-ram)).
- A free [playit.gg](https://playit.gg) account. This is what lets friends connect over the internet.
- About 15 minutes.

## 🚀 Setup

### 1. 🐳 Install a container runtime

This runs the server in a self-contained box, so you don't have to install Java, Steam, or anything game-related by hand. Pick one and install it, then open it once so it's running:

- **Mac:** [OrbStack](https://orbstack.dev) (lighter) or [Docker Desktop](https://www.docker.com/products/docker-desktop/).
- **Windows / Linux:** [Docker Desktop](https://www.docker.com/products/docker-desktop/).

The commands below use `docker compose`. If you picked a different runtime, swap in its command.

### 2. 🎟️ Get your playit key

playit.gg gives your server a public address so friends can join without you touching your router.

Open this exact link, sign up (free), name the agent, and copy the secret it shows you:

```
https://playit.gg/account/setup/wizard/new-account/docker/docker-name
```

Use that link. It's the "Docker" path and it's easy to miss in their menus. (The playit desktop app is a separate thing you don't need.)

### 3. ⚙️ Fill in your settings

In this folder, make your own copy of the example settings:

```bash
cp .env.example .env
```

Open `.env` in any text editor and set at least these:

- `PLAYIT_SECRET_KEY` — paste the key from step 2.
- `PASSWORD` — what friends type to join.
- `ADMINPASSWORD` — your admin login. The server won't start without it.

One rule: don't put a `# comment` at the end of a `KEY=value` line. Everything after the `=` becomes the value. Keep notes on their own lines.

### 4. ▶️ Start the server

Open a terminal in this folder and run:

```bash
docker compose up -d      # download + start in the background
docker compose logs -f    # watch it boot (first run builds the world, takes a few minutes)
```

When the logs go quiet and steady, it's live. Press `Ctrl-C` to stop watching — the server keeps running.

To stop the server later: `docker compose down`. Your world is saved.

### 5. 🚇 Open the tunnel

In the [playit.gg dashboard](https://playit.gg), create **one** tunnel:

- **Type:** Project Zomboid (or set Protocol **UDP**, Port Count **2**)
- **Local address:** `172.28.0.10`   **Local port:** `16261`

It gives you a public address like `something.playit.gg:PORT`. Type `172.28.0.10` exactly — a name won't work.

### 6. 🎮 Connect in-game

You and your friends open Project Zomboid → **Join → Add Server / connect by IP**, enter the playit address and port, **uncheck "Use Steam Relay"**, and join with the `PASSWORD`.

Give friends only the **first** port number. The game uses the next one on its own.

## 🧠 Adjusting RAM

The server is set to 8 GB, which is comfortable for a normal group. To change it, edit these in `.env`:

- `MAX_MEMORY=8192m` — the game's memory. Drop to `4096m` if it's just a few of you.
- `CONTAINER_MEMORY=10g` — keep this a little above `MAX_MEMORY` (use `6g` if you dropped to 4 GB).

## 🔄 Updating

The version is pinned in `docker-compose.yaml` (the `image:` line ends in `42.20.0-release`), so it won't change on its own. That's on purpose: a surprise Build 42 patch can break your save. To update when you're ready, back up `server-data/Zomboid` first, bump that tag to the newer build, then run:

```bash
docker compose pull && docker compose up -d --force-recreate
```

A patch-level bump leaves your world in `server-data/` untouched — but read the patch notes first. An update that adds **map content** invalidates existing saves outright, and then the world has to be regenerated rather than migrated. Keep backups.

> **Build 42 is stable now.** As of `42.20.0` (released 2026-07-29) Build 42 ships on Steam's normal branch, so tags end in `-release`, not `-unstable`, and your friends need no beta opt-in — a stock, auto-updating client just connects.
>
> Two things this changed:
> - `:latest` and `:latest-release` now mean **Build 42**, not Build 41. If you specifically want Build 41, pin `41.78.19-release` and have players select Steam's `legacy41` branch.
> - Worlds made on `42.19.0-unstable` **cannot** load on 42.20 (it added map content). This server's 42.19 world was archived and regenerated on 2026-07-29. To finish an old 42.19 world instead, keep the old tag *and* have every player select Steam's `42.19` branch.

## 💾 Backups

Everything the server writes lives in `server-data/`. The one to back up is `server-data/Zomboid/` — that's your world, saves, and players. Copy it somewhere safe now and then.

**Turn on autosave (do this once).** Out of the box the world only saves when players leave or you shut down cleanly, so a crash can cost you the whole session. Stop the server, open `server-data/Zomboid/Server/<your-server-name>.ini`, change `SaveWorldEveryMinutes=0` to `15`, and start it again:

```bash
docker compose stop pz
# edit the .ini, then:
docker compose start pz
```

For a guaranteed save before stopping, run `docker compose run --rm rcon save`, then stop. (Or the manual way: `docker attach pz`, type `save`, then `quit`; detach without stopping with `Ctrl-P` then `Ctrl-Q`.)

## 🧩 Mods: the one thing that breaks players

Mods come from the Steam Workshop, which is what makes them easy — your players just get them automatically on connect. The catch is that **the server pulls the newest version of every mod each time it starts**, and a mod author's update can rename the mod's internal ID. When that happens, your server asks for an ID that no client can load and *everyone* fails to join with a mod mismatch. There is no way to pin a Workshop mod to a version — Steam only ever serves "latest" — so instead, check:

```bash
./scripts/check-mods.sh          # both checks below
./scripts/check-mods.sh drift    # what will re-download on the next restart
./scripts/check-mods.sh ids      # does every mod in MOD_IDS still resolve
```

Exit code 0 means clean. Run it from the repo root (the scripts `cd` there themselves, so it works from anywhere). Two moments matter:

- **Before a restart** — `drift` asks Steam what's changed. `scripts/graceful-stop.sh` now does this for you automatically.
- **After a restart that pulled something** — `ids` confirms nothing got renamed. If something did, it names the replacement ID to paste into `MOD_IDS` in `.env`.

Then tell players to **fully restart Project Zomboid once** after any restart that pulled an update, so Steam refreshes their copy to the same version the server has. That's the whole player-side workflow.

## 🧹 Starting over

```bash
docker compose down
rm -rf server-data/Zomboid server-data/workshop
```

This is permanent. The world, saves, and mods are gone.

## 🍏 Why this works anywhere

Project Zomboid's server is normally a pain to install, especially on Apple Silicon. This uses a prebuilt image with the server already inside, so your computer never runs the fragile install step. It just runs the game. That's the whole trick. (The gory details are in the comments of `docker-compose.yaml` if you're curious.)

## 🔐 A note on secrets

Your `.env` (key and passwords) and `server-data/` are never committed to git. Keep it that way.

Happy surviving. 🧟
