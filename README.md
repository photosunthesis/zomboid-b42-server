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

```bash
docker compose pull && docker compose up -d --force-recreate
```

The server is baked into the image, so a fresh pull *is* the update. Your world in `server-data/` is untouched. Build 42 is still a beta, so updates can occasionally break saves — keep backups.

## 💾 Backups

Everything the server writes lives in `server-data/`. The one to back up is `server-data/Zomboid/` — that's your world, saves, and players. Copy it somewhere safe now and then.

For a guaranteed save before stopping, run `docker attach pz`, type `save`, then `quit`. (To detach without stopping: `Ctrl-P` then `Ctrl-Q`.)

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
