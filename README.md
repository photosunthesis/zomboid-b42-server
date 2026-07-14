# 🧟 Project Zomboid B42 Dedicated Server

A dead-simple **Project Zomboid (Build 42) dedicated server** that runs on **any OS with any container runtime**, exposed to friends over the internet through a [playit.gg](https://playit.gg) tunnel — **no router port-forwarding, no public IP, no custom build.**

Everything lives in two files: [`docker-compose.yaml`](docker-compose.yaml) and your `.env`. 🎉

---

## 🧰 What you need

- 🐳 **A container runtime that speaks Compose** — Docker, OrbStack, or whatever you prefer. If it can run a `compose` file, it can run this.
- 🎟️ A free **[playit.gg](https://playit.gg)** account (for the tunnel)
- 💾 ~8–16 GB RAM to spare — B42 multiplayer is hungry
- 💻 Any OS — Linux, macOS (Intel or Apple Silicon), or Windows

> 📝 **Commands below use `docker compose`.** If your runtime uses a different invocation, just substitute it — the compose file itself is standard and doesn't care which runtime brings it up.

---

## 🍏 Why it runs anywhere

Project Zomboid's server is x86-only, and it's normally installed by **SteamCMD** — whose bootstrap is a **32-bit x86 binary**. That install step is the fragile part, especially on **ARM64 hosts** (Apple Silicon, Raspberry Pi, ARM cloud VMs), where a 32-bit x86 binary can't be emulated cleanly. 💥

This setup sidesteps the problem entirely:

- 📦 It uses the **[danixu86 prebuilt image](https://hub.docker.com/r/danixu86/project-zomboid-dedicated-server)** with the server files **baked in at build time** (SteamCMD ran on danixu's amd64 CI, not on your machine).
- ⚙️ At runtime, only the **64-bit Java server** runs — no SteamCMD — so the same image behaves identically everywhere:
  - 🟢 On **x86-64 hosts** (most PCs & servers, Intel Macs) it runs **natively**.
  - 🟡 On **ARM64 hosts** it runs under lightweight emulation — and, crucially, *works at all*, because you never have to run the 32-bit SteamCMD bootstrap.
- 🚇 A **playit.gg agent** rides alongside on a private bridge network and forwards internet traffic to the server. Your friends get a public address; your router stays untouched.

---

## 🚀 Quick start

```bash
cp .env.example .env          # then edit it (playit key, passwords, ...)
docker compose up -d          # pull images + start in the background
docker compose logs -f        # watch the logs (first boot loads the world)
docker compose down           # stop + remove containers (world data persists)
```

First boot takes a bit while the world generates. ⏳ Once you see the server settle in the logs, you're live.

---

## 🔑 Configuration

All settings live in **`.env`** (copied from [`.env.example`](.env.example)). The essentials:

| Variable | What it does |
|---|---|
| `PLAYIT_SECRET_KEY` | 🎟️ Secret for the headless playit agent (see below) |
| `SERVERNAME` | 🏷️ Server name |
| `PASSWORD` | 🔒 Password friends type to join |
| `ADMINPASSWORD` | 👑 In-game admin login — **mandatory**, server won't start without it |
| `RCONPASSWORD` | 🎛️ Remote console password |
| `MAX_MEMORY` | 🧠 Java heap (B42 MP wants a lot — 12G is generous) |
| `MOD_IDS` / `WORKSHOP_IDS` | 🧩 Steam Workshop mods (optional — see caveat below) |

> ⚠️ **Values are passed to the container literally** (`env_file` uses `format: raw`). Don't put a trailing `# comment` on a `KEY=VALUE` line — the whole thing after `=` becomes the value. Keep comments on their own lines. (The `env_file` long syntax needs a reasonably recent Compose implementation; any current runtime is fine.)

### 🎟️ Getting your playit key

Generate a **Docker** agent secret from this direct link (easy to miss in the site's menus):

```
https://playit.gg/account/setup/wizard/new-account/docker/docker-name
```

Name the agent, copy the secret, paste it into `PLAYIT_SECRET_KEY`. (This is the "Docker" path — it works with any runtime; the click-a-claim-URL flow is playit's *desktop* app, which is a different thing.)

---

## 🎮 How friends connect

1. In the **playit.gg dashboard**, create **one** tunnel:
   - **Type** = `Project Zomboid` (or: Protocol **UDP**, Port Count **2**)
   - **Local address** = `172.28.0.10`  **Local port** = `16261`

   > 📌 `172.28.0.10` is the server's fixed IP on the private bridge. The agent has no DNS, so this must be the literal IP — a service name like `pz` will **not** work.

   playit gives you a public address like `something.playit.gg:PORT`.

2. **In-game:** `Join → Add Server / connect by IP` → enter that host + public port, **uncheck "Use Steam Relay"**, and join with your `PASSWORD`.

   > 🔢 Give friends only the **first** port — PZ uses the `+1` port itself (that's why the tunnel covers 2 ports).

---

## 🔄 Updating to a new B42 patch

```bash
docker compose pull && docker compose up -d --force-recreate
```

The server install lives in the image, so **a fresh pull *is* the update**. Your world in `./server-data/` is untouched. 🌍

> 🧪 **B42 is a beta (unstable) branch.** Expect bugs, updates can occasionally break saves, keep the group small (Indie Stone suggests ≤ 20 + whitelisting), and give it plenty of RAM. If clients auto-update to a patch newer than danixu has published, they can't join until the image catches up — pin a specific image tag (e.g. `:42.19.0-unstable`) in `docker-compose.yaml` to freeze the version.

---

## 💾 Backups & persistent data

Everything the server writes lives in **`./server-data/`** (bind-mounted, survives `down` and image updates):

- `Zomboid/` — 🌍 your world, saves, server `.ini`, player DB, logs → **this is what you back up**
- `workshop/` — 🧩 downloaded Steam Workshop mods

> 💡 **For a guaranteed save before stopping:** the image doesn't trap `SIGTERM`, so a plain `docker compose stop` relies on PZ's autosave (you may lose a few minutes). To force it: `docker attach pz`, type `save` then `quit`. Detach without stopping with `Ctrl-P` `Ctrl-Q`.

---

## 🧹 Starting fresh

To wipe the world and start over, bring the stack down and remove the persisted data:

```bash
docker compose down            # stop + remove containers and the compose network
rm -rf server-data/Zomboid server-data/workshop
```

⚠️ This is **permanent** — world saves, logs, and workshop mods all go.

---

## 🩹 Troubleshooting

- **😱 Scary playit ERROR lines on startup** (`Network unreachable` / `failed to ping tunnel server` on an IPv6 address) — **benign.** The container has no IPv6, so the agent's first (IPv6) control-server candidate fails instantly and falls through to IPv4. You'll see `playit connected; tunnels loaded` right after.
- **🛌 Server dies while you're away** — almost always the **host slept, rebooted, or the runtime didn't restart**. Two things to check on any machine you use as a server:
  1. **Keep the host awake** — a sleeping machine suspends the whole container runtime, and no restart policy can help. Disable sleep in your OS power settings (or use a keep-awake utility for your platform).
  2. **Make the runtime start on boot / login**, so the `restart:` policy in the compose file can actually bring the stack back. If your runtime doesn't auto-start the stack after *its own* restart, switch both services to `restart: always` in `docker-compose.yaml`.
- **🚪 Friends can't join** — double-check the tunnel's Local address is `172.28.0.10:16261`, that they **unchecked "Use Steam Relay"**, and that they're using the **first** public port. Try flipping `NOSTEAM` in `.env`.
- **🧩 Mods won't download** — Workshop mods need SteamCMD (`FORCEUPDATE=True`), which hits the same 32-bit path that's unreliable on ARM64 hosts. A vanilla server needs none of this.

---

## 🔐 A note on secrets

`.env` (your playit key + passwords) and `server-data/` are **gitignored** — they never get committed. Keep it that way. 🙈

---

Happy surviving. 🧟🔨
